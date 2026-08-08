# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "set"

module Memury
  module Ai
    class TeachingDiagnosisService
      Result = Struct.new(
        :diagnostic,
        :source,
        :fallback_reason,
        :compatibility_note,
        :latency_ms,
        keyword_init: true
      )

      DEFAULT_OPEN_TIMEOUT_SECONDS = 5
      DEFAULT_READ_TIMEOUT_SECONDS = 20
      DEFAULT_WRITE_TIMEOUT_SECONDS = 10
      DEFAULT_MAX_OUTPUT_TOKENS = 500

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(course_or_subject:, knowledge_point:, question:, student_answer:, learner_state_summary:, scoring_basis: nil, logger: Rails.logger)
        @course_or_subject = course_or_subject
        @knowledge_point = knowledge_point
        @question = question
        @student_answer = student_answer.to_s
        @learner_state_summary = learner_state_summary
        @scoring_basis = scoring_basis
        @logger = logger
      end

      def call
        return fallback_result("AI diagnosis disabled") unless ai_enabled?
        return fallback_result("OPENAI_API_KEY missing") if openai_api_key.blank?
        return fallback_result("OPENAI_BASE_URL missing") if openai_base_url.blank?
        return fallback_result("MEMURY_AI_MODEL missing") if model.blank?

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = perform_request
        latency_ms = elapsed_ms(start_time)
        return result.tap { |r| r.latency_ms = latency_ms } if result.is_a?(Result)

        fallback_result(fallback_reason(result), latency_ms:)
      rescue StandardError => e
        fallback_result(error_reason(e), latency_ms: elapsed_ms(start_time))
      end

      private

      attr_reader :course_or_subject, :knowledge_point, :question, :student_answer, :learner_state_summary,
                  :scoring_basis, :logger

      def ai_enabled?
        parse_boolean_env("MEMURY_AI_ENABLED")
      end

      def parse_boolean_env(name)
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

      def open_timeout_seconds
        integer_env("MEMURY_AI_OPEN_TIMEOUT_SECONDS", DEFAULT_OPEN_TIMEOUT_SECONDS)
      end

      def read_timeout_seconds
        integer_env("MEMURY_AI_READ_TIMEOUT_SECONDS", DEFAULT_READ_TIMEOUT_SECONDS)
      end

      def write_timeout_seconds
        integer_env("MEMURY_AI_WRITE_TIMEOUT_SECONDS", DEFAULT_WRITE_TIMEOUT_SECONDS)
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
        payload = request_payload
        response = post_json(responses_endpoint, payload)
        return parse_response(response) if response.is_a?(Net::HTTPSuccess)

        @compatibility_note = compatibility_note_for(response)

        response
      end

      def request_payload
        payload = {
          model:,
          instructions: prompt[:instructions],
          input: prompt[:input],
          text: {
            format: {
              type: "json_schema",
              name: "memury_teaching_diagnosis",
              strict: true,
              schema: TeachingDiagnosisSchema.provider_schema
            }
          },
          max_output_tokens:
        }
        payload[:store] = false
        payload
      end

      def prompt
        @prompt ||= TeachingDiagnosisPrompt.build(
          course_or_subject:,
          knowledge_point:,
          question:,
          scoring_basis: scoring_basis,
          student_answer: student_answer,
          learner_state_summary: learner_state_summary
        )
      end

      def responses_endpoint
        @responses_endpoint ||= URI.join(base_uri_with_trailing_slash, "responses")
      end

      def base_uri_with_trailing_slash
        uri = URI.parse(openai_base_url)
        uri.path = "#{uri.path}/" unless uri.path.end_with?("/")
        uri.to_s
      rescue URI::InvalidURIError
        openai_base_url
      end

      def post_json(uri, payload)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout_seconds
        http.read_timeout = read_timeout_seconds
        http.write_timeout = write_timeout_seconds if http.respond_to?(:write_timeout=)

        headers = {
          "Authorization" => "Bearer #{openai_api_key}",
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = JSON.generate(payload)

        logger.info("Memury AI request | model=#{model} | endpoint=#{uri.host}#{uri.path} | store=#{payload.key?(:store) ? payload[:store] : 'omitted'} | student_answer_chars=#{student_answer.length}")
        http.start { |client| client.request(request) }
      rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
        raise e
      end

      def parse_response(response)
        body = response.body.to_s
        raise StandardError, "empty response" if body.blank?

        payload = JSON.parse(body)
        assert_eligible_response!(payload)
        candidate_text = extract_output_text(payload)
        raise StandardError, "empty output text" if candidate_text.blank?

        json = parse_candidate_json(candidate_text)
        raise StandardError, "invalid JSON" if json.blank?

        validate_diagnostic!(json)
        normalized = normalize_diagnostic(json)
        Result.new(diagnostic: normalized, source: "ai", fallback_reason: nil, compatibility_note: nil, latency_ms: nil)
      rescue JSON::ParserError, StandardError => e
        raise StandardError, e.message
      end

      def extract_output_text(payload)
        return payload if payload.is_a?(String)
        return nil unless payload.is_a?(Hash)

        output_text = payload["output_text"]
        return output_text.strip if output_text.is_a?(String) && output_text.present?

        Array(payload["output"]).each do |item|
          text = extract_text_from_output_item(item)
          return text if text.present?
        end

        nil
      end

      def assert_eligible_response!(payload)
        raise StandardError, "invalid response envelope" unless payload.is_a?(Hash)
        raise StandardError, "response incomplete" unless payload["status"].to_s == "completed"
        raise StandardError, "response incomplete" if payload["incomplete_details"].present?
        raise StandardError, "response error" if payload["error"].present?

        output = payload["output"]
        return if top_level_output_text?(payload) && output.blank?

        raise StandardError, "empty output" unless output.is_a?(Array) && output.any?

        output.each do |item|
          validate_output_item!(item)
        end
      end

      def top_level_output_text?(payload)
        payload["output_text"].is_a?(String) && payload["output_text"].present?
      end

      def validate_output_item!(item)
        raise StandardError, "invalid output item" unless item.is_a?(Hash)
        raise StandardError, "response incomplete" unless item["status"].to_s == "completed"
        raise StandardError, "unsupported output type" unless item["type"].to_s == "message"

        content = item["content"]
        raise StandardError, "empty content" unless content.is_a?(Array) && content.any?

        content.each do |content_item|
          validate_content_item!(content_item)
        end
      end

      def validate_content_item!(content_item)
        raise StandardError, "invalid content item" unless content_item.is_a?(Hash)

        type = content_item["type"].to_s
        case type
        when "output_text"
          raise StandardError, "empty output text" unless content_item["text"].is_a?(String) && content_item["text"].present?
        when "refusal"
          raise StandardError, "refusal received"
        else
          raise StandardError, "unsupported content type"
        end
      end

      def extract_text_from_output_item(item)
        return nil unless item.is_a?(Hash)

        item = item.with_indifferent_access
        return item[:text].to_s if item[:type] == "output_text" && item[:text].present?

        Array(item[:content]).each do |content|
          text = extract_text_from_content_item(content)
          return text if text.present?
        end

        nil
      end

      def extract_text_from_content_item(content)
        return nil unless content.is_a?(Hash)

        content = content.with_indifferent_access
        return nil unless content[:text].is_a?(String) && content[:text].present?
        return nil if content[:type].present? && content[:type] != "output_text"

        content[:text].to_s
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
        return false if text.match?(/```|<[^>]+>|<\/\w+>/i)
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

      def longest_common_substring_length(a, b)
        return 0 if a.blank? || b.blank?

        previous = Array.new(b.length + 1, 0)
        longest = 0

        a.each_char do |char_a|
          current = Array.new(b.length + 1, 0)
          b.each_char.with_index(1) do |char_b, index|
            if char_a == char_b
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
        [12, [compact_reference.length - 2, 6].max].min
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
        Result.new(
          diagnostic: TeachingDiagnosisFallback.build(
            course_or_subject:,
            knowledge_point:,
            question:,
            scoring_basis: scoring_basis,
            student_answer: student_answer,
            learner_state_summary: learner_state_summary
          ),
          source: "rule_fallback",
          fallback_reason: fallback_reason(reason),
          compatibility_note: @compatibility_note,
          latency_ms:
        )
      ensure
        logger.info("Memury AI fallback | reason=#{fallback_reason(reason)}")
      end

      def fallback_reason(reason)
        return reason if reason.is_a?(String)
        return "http #{reason.code}" if reason.respond_to?(:code)

        reason.class.name
      end

      def error_reason(error)
        case error
        when Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
          "request timed out"
        when SocketError, SystemCallError, OpenSSL::SSL::SSLError
          "connection failed"
        else
          error.message.presence || "request failed"
        end
      end

      def compatibility_note_for(response)
        return nil unless response.respond_to?(:code)
        return nil unless [400, 422].include?(response.code.to_i)

        body = response.body.to_s
        return "structured outputs rejected" if body.match?(/text\.format|json_schema|structured output|unsupported|additional properties/i)

        "provider rejected request"
      end

      def elapsed_ms(start_time)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      end
    end
  end
end
