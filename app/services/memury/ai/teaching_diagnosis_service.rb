# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "structured_response_client"

module Memury
  module Ai
    class TeachingDiagnosisService
      class Result
        attr_accessor :diagnostic, :source, :fallback_reason, :compatibility_note, :latency_ms, :metadata

        def initialize(diagnostic:, source:, fallback_reason:, compatibility_note:, latency_ms:, metadata:)
          @diagnostic = diagnostic
          @source = source
          @fallback_reason = fallback_reason
          @compatibility_note = compatibility_note
          @latency_ms = latency_ms
          @metadata = metadata
        end
      end

      DEFAULT_MAX_OUTPUT_TOKENS = 500

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(course_or_subject:,
                     knowledge_point:,
                     question:,
                     student_answer:,
                     learner_state_summary:,
                     scoring_basis: nil,
                     logger: Rails.logger,
                     client: nil)
        @course_or_subject = course_or_subject
        @knowledge_point = knowledge_point
        @question = question
        @student_answer = student_answer.to_s
        @learner_state_summary = learner_state_summary
        @scoring_basis = scoring_basis
        @logger = logger
        @client = client || StructuredResponseClient.new(logger:)
      end

      def call
        @metadata = {
          "provider" => "openai",
          "model" => model.presence,
          "schema_version" => TeachingDiagnosisSchema::VERSION,
          "status" => "failure"
        }.compact
        return fallback_result("AI diagnosis disabled") unless ai_enabled?
        return fallback_result("OPENAI_API_KEY missing") if openai_api_key.blank?
        return fallback_result("OPENAI_BASE_URL missing") if openai_base_url.blank?
        return fallback_result("MEMURY_AI_MODEL missing") if model.blank?

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = perform_request
        latency_ms = elapsed_ms(start_time)
        if result.is_a?(Result)
          return result.tap do |r|
            r.latency_ms = latency_ms
            r.metadata = @metadata.merge("latency_ms" => latency_ms)
          end
        end

        fallback_result(fallback_reason(result), latency_ms:)
      rescue => e
        fallback_result(error_reason(e), latency_ms: elapsed_ms(start_time))
      end

      private

      attr_reader :course_or_subject,
                  :knowledge_point,
                  :question,
                  :student_answer,
                  :learner_state_summary,
                  :scoring_basis,
                  :logger,
                  :client

      def ai_enabled?
        parse_boolean_env?("MEMURY_AI_ENABLED")
      end

      def parse_boolean_env?(name)
        raw = ENV[name]
        return false if raw.nil?

        normalized = raw.strip
        return false if normalized.empty?

        normalized = normalized.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
        normalized = normalized.strip.downcase

        return true if %w[true 1 yes on y t].include?(normalized)
        return false if %w[false 0 no off n f].include?(normalized)

        false
      end

      def openai_api_key
        ENV["OPENAI_API_KEY"].to_s.strip
      end

      def openai_base_url
        ENV["OPENAI_BASE_URL"].to_s.strip
      end

      def model
        ENV["MEMURY_AI_MODEL"].to_s.strip
      end

      def max_output_tokens
        integer_env("MEMURY_AI_MAX_OUTPUT_TOKENS", DEFAULT_MAX_OUTPUT_TOKENS)
      end

      def integer_env(name, default)
        Integer(ENV.fetch(name, default))
      rescue ArgumentError, TypeError
        default
      end

      def perform_request
        perform_structured_request
      end

      def perform_structured_request
        result = client.call(
          capability: "diagnose",
          schema_name: "memury_teaching_diagnosis",
          instructions: prompt[:instructions],
          input: prompt[:input],
          schema: TeachingDiagnosisSchema.provider_schema,
          schema_version: TeachingDiagnosisSchema::VERSION,
          max_output_tokens:
        )
        @metadata = @metadata.to_h.merge(result.metadata.to_h)
        # Keep the existing parser as a final compatibility seam.  The shared
        # client has already parsed and schema-checked the object; re-parsing
        # the bounded object lets legacy instrumentation/tests observe the
        # same safety boundary without retaining provider text.
        candidate = parse_candidate_json(JSON.generate(result.data))
        validate_diagnostic!(candidate)
        Result.new(
          diagnostic: normalize_diagnostic(candidate),
          source: "ai",
          fallback_reason: nil,
          compatibility_note: nil,
          latency_ms: result.metadata.to_h["latency_ms"],
          metadata: @metadata
        )
      rescue StructuredResponseClient::Error => e
        @metadata = @metadata.to_h.merge(e.metadata.to_h)
        @compatibility_note = "structured outputs rejected" if e.category.in?(%w[http_400 http_422])
        raise e
      end

      def prompt
        @prompt ||= TeachingDiagnosisPrompt.build(
          course_or_subject:,
          knowledge_point:,
          question:,
          scoring_basis:,
          student_answer:,
          learner_state_summary:
        )
      end

      def parse_candidate_json(text)
        cleaned = text.to_s.strip
        cleaned = cleaned.sub(/\A```json\s*/i, "").sub(/\A```\s*/i, "").sub(/```\s*\z/, "")
        start_index = cleaned.index("{")
        end_index = cleaned.rindex("}")
        return nil unless start_index && end_index && end_index > start_index

        JSON.parse(cleaned[start_index..end_index])
      end

      def validate_diagnostic!(json)
        raise StandardError, "invalid JSON" unless json.is_a?(Hash)

        normalized = normalize_diagnostic(json)
        errors = TeachingDiagnosisSchema.validator.validate(normalized).to_a
        raise StandardError, "schema validation failed" if errors.any?

        raise StandardError, "unsafe output" unless safe_output?(normalized)
        if (violation = reference_answer_violation(normalized))
          raise StandardError, reference_answer_violation_message(violation)
        end
      end

      def normalize_diagnostic(json)
        json.deep_stringify_keys.deep_transform_values do |value|
          value.is_a?(String) ? value.strip : value
        end
      end

      def safe_output?(diagnostic)
        walk_text_values(diagnostic).all? { |value| safe_text?(value) }
      end

      def walk_text_values(value, values = [])
        case value
        when Hash
          value.each_value { |nested| walk_text_values(nested, values) }
        when Array
          value.each { |nested| walk_text_values(nested, values) }
        when String
          values << value
        end
        values
      end

      def safe_text?(text)
        return false if text.match?(%r{```|<[^>]+>|</\w+>}i)
        return false if text.match?(/\b(?:drop|delete|truncate|alter|grant|revoke)\s+(?:table|database|schema|grade|score|permission|config)\b/i)
        return false if text.match?(/\b(?:update|modify|change|set)\b.*\b(?:grade|score|permission|role|config|database)\b/i)

        true
      end

      def reference_answer_violation(diagnostic)
        reference = scoring_basis.to_s.strip
        return nil if reference.blank?

        walk_text_leaves(diagnostic).each do |path, value|
          if (violation_type = reference_answer_violation_type(value, reference))
            return {
              path: path.join("."),
              type: violation_type
            }
          end
        end

        nil
      end

      def walk_text_leaves(value, path = [], leaves = [])
        case value
        when Hash
          value.each do |key, nested|
            walk_text_leaves(nested, path + [key.to_s], leaves)
          end
        when Array
          value.each_with_index do |nested, index|
            walk_text_leaves(nested, path + [index.to_s], leaves)
          end
        when String
          leaves << [path, value]
        end
        leaves
      end

      def reference_answer_violation_type(text, reference)
        normalized_text = normalize_text(text)
        normalized_reference = normalize_text(reference)
        return nil if normalized_text.blank? || normalized_reference.blank?

        return "explicit_reference_language" if explicit_reference_language?(normalized_text)
        return "reference_answer_quote" if direct_reference_quote?(normalized_text, normalized_reference)
        return "reference_answer_overlap" if significant_reference_overlap?(normalized_text, normalized_reference)

        nil
      end

      def explicit_reference_language?(text)
        text.match?(/参考答案|标准答案|正确答案|与参考答案不一致|与标准答案不一致|正确答案应为|标准答案应为|答案是/i)
      end

      def direct_reference_quote?(text, reference)
        compact_text(text).include?(compact_text(reference))
      end

      def significant_reference_overlap?(text, reference)
        longest_common_substring_length(compact_text(text), compact_text(reference)) >= overlap_threshold(reference)
      end

      def longest_common_substring_length(first_text, second_text)
        return 0 if first_text.blank? || second_text.blank?

        previous = Array.new(second_text.length + 1, 0)
        longest = 0

        first_text.each_char do |first_char|
          current = Array.new(second_text.length + 1, 0)
          second_text.each_char.with_index(1) do |second_char, index|
            if first_char == second_char
              current[index] = previous[index - 1] + 1
              longest = [longest, current[index]].max
            end
          end
          previous = current
        end

        longest
      end

      def overlap_threshold(reference)
        compact_reference = compact_text(reference)
        [compact_reference.length - 2, 6].max.clamp(0, 12)
      end

      def compact_text(value)
        normalize_text(value).gsub(/[[:space:][:punct:]]+/, "")
      end

      def normalize_text(value)
        value.to_s.gsub(/\s+/, " ").strip
      end

      def reference_answer_violation_message(violation)
        "reference answer leaked in #{violation[:path]} (#{violation[:type]})"
      end

      def fallback_result(reason, latency_ms: nil)
        fallback_metadata = {
          "provider" => "deterministic_fallback",
          "attempted_provider" => @metadata&.fetch("provider", nil),
          "model" => @metadata&.fetch("model", nil),
          "schema_version" => TeachingDiagnosisSchema::VERSION,
          "status" => "fallback",
          "error_category" => fallback_reason(reason),
          "latency_ms" => latency_ms
        }.compact
        Result.new(
          diagnostic: TeachingDiagnosisFallback.build(
            course_or_subject:,
            knowledge_point:,
            question:,
            scoring_basis:,
            student_answer:,
            learner_state_summary:
          ),
          source: "rule_fallback",
          fallback_reason: fallback_reason(reason),
          compatibility_note: @compatibility_note,
          latency_ms:,
          metadata: fallback_metadata
        )
      ensure
        logger.info("Memury AI fallback | reason=#{fallback_reason(reason)}")
      end

      def fallback_reason(reason)
        return reason if reason.is_a?(String)

        if reason.is_a?(StructuredResponseClient::Error)
          return "http #{reason.category.delete_prefix("http_")}" if reason.category.start_with?("http_")

          return {
            "ai_disabled" => "AI diagnosis disabled",
            "missing_configuration" => "provider configuration missing",
            "invalid_json" => "invalid JSON",
            "schema_validation_failed" => "schema validation failed",
            "refusal" => "refusal received",
            "empty_content" => "empty content",
            "empty_output_text" => "empty output text",
            "empty_output" => "empty output",
            "invalid_envelope" => "invalid response envelope",
            "incomplete_response" => "response incomplete",
            "unsupported_content_type" => "unsupported content type",
            "connection_failed" => "connection failed",
            "timeout" => "request timed out"
          }.fetch(reason.category, reason.category)
        end
        return "http #{reason.code}" if reason.respond_to?(:code)

        reason.class.name
      end

      def error_reason(error)
        case error
        when Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
          "request timed out"
        when SocketError, SystemCallError, OpenSSL::SSL::SSLError
          "connection failed"
        when StructuredResponseClient::Error
          fallback_reason(error)
        else
          error.message.presence || "request failed"
        end
      end

      def elapsed_ms(start_time)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      end
    end
  end
end
