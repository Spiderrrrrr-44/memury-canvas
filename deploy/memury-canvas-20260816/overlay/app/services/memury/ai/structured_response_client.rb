# frozen_string_literal: true

require "json"
require "json_schemer"
require "net/http"
require "openssl"
require "uri"

module Memury
  module Ai
    # Shared server-side Responses API transport for every structured teaching
    # capability. It owns network/error/schema handling; providers own roles,
    # minimal contexts, and deterministic fallback policy.
    class StructuredResponseClient
      class Result
        attr_accessor :data, :metadata

        def initialize(data:, metadata:)
          @data = data
          @metadata = metadata
        end
      end

      class Error < StandardError
        attr_reader :category, :metadata

        def initialize(message, category:, metadata: {})
          super(message)
          @category = category.to_s
          @metadata = metadata
        end
      end

      DEFAULT_OPEN_TIMEOUT_SECONDS = 5
      DEFAULT_READ_TIMEOUT_SECONDS = 20
      DEFAULT_WRITE_TIMEOUT_SECONDS = 10
      DEFAULT_MAX_OUTPUT_TOKENS = 700

      def initialize(logger: Rails.logger, env: ENV)
        @logger = logger
        @env = env
      end

      def call(
        capability:,
        instructions:,
        input:,
        schema:,
        schema_version:,
        max_output_tokens: DEFAULT_MAX_OUTPUT_TOKENS,
        schema_name: nil
      )
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        metadata = base_metadata(capability:, schema_version:)
        ensure_configured!(metadata)

        response = post_json(
          uri: responses_endpoint,
          payload: request_payload(capability:, instructions:, input:, schema:, max_output_tokens:, schema_name:)
        )
        parsed = parse_response(response, schema:, metadata:)
        latency_ms = elapsed_ms(started_at)
        Result.new(data: parsed, metadata: metadata.merge("latency_ms" => latency_ms, "status" => "success"))
      rescue Error => e
        e.metadata["latency_ms"] ||= elapsed_ms(started_at)
        raise
      rescue => e
        category = case e
                   when JSON::ParserError then "invalid_json"
                   when Net::OpenTimeout, Net::ReadTimeout, Timeout::Error then "timeout"
                   when SocketError, SystemCallError, OpenSSL::SSL::SSLError then "connection_failed"
                   when URI::InvalidURIError then "invalid_base_url"
                   else "provider_error"
                   end
        raise structured_error(category, e.message, metadata:, started_at:)
      end

      private

      attr_reader :logger, :env

      def base_metadata(capability:, schema_version:)
        {
          "provider" => "openai",
          "capability" => capability.to_s,
          "model" => env["MEMURY_AI_MODEL"].to_s.strip.presence,
          "schema_version" => schema_version.to_s,
          "status" => "failure"
        }.compact
      end

      def ensure_configured!(metadata)
        unless parse_boolean_env?("MEMURY_AI_ENABLED")
          raise Error.new("AI diagnosis disabled", category: "ai_disabled", metadata:)
        end

        return if env["OPENAI_API_KEY"].to_s.strip.present? && env["OPENAI_BASE_URL"].to_s.strip.present? && env["MEMURY_AI_MODEL"].to_s.strip.present?

        missing = %w[OPENAI_API_KEY OPENAI_BASE_URL MEMURY_AI_MODEL].reject { |key| env[key].to_s.strip.present? }
        raise Error.new("missing provider configuration: #{missing.join(",")}", category: "missing_configuration", metadata:)
      end

      def parse_boolean_env?(name)
        %w[true 1 yes on y t].include?(env[name].to_s.strip.delete_prefix('"').delete_suffix('"').downcase)
      end

      def request_payload(capability:, instructions:, input:, schema:, max_output_tokens:, schema_name: nil)
        {
          model: env.fetch("MEMURY_AI_MODEL").to_s.strip,
          instructions: instructions.to_s,
          input: input.is_a?(String) ? input : JSON.generate(input),
          text: {
            format: {
              type: "json_schema",
              name: schema_name.presence || "memury_#{capability}",
              strict: true,
              schema:
            }
          },
          max_output_tokens: max_output_tokens.to_i,
          store: false
        }
      end

      def responses_endpoint
        base_url = env.fetch("OPENAI_BASE_URL").to_s.strip
        uri = URI.parse(base_url)
        uri.path = "#{uri.path}/" unless uri.path.end_with?("/")
        URI.join(uri.to_s, "responses")
      end

      def post_json(uri:, payload:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = integer_env("MEMURY_AI_OPEN_TIMEOUT_SECONDS", DEFAULT_OPEN_TIMEOUT_SECONDS)
        http.read_timeout = integer_env("MEMURY_AI_READ_TIMEOUT_SECONDS", DEFAULT_READ_TIMEOUT_SECONDS)
        http.write_timeout = integer_env("MEMURY_AI_WRITE_TIMEOUT_SECONDS", DEFAULT_WRITE_TIMEOUT_SECONDS) if http.respond_to?(:write_timeout=)
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Authorization"] = "Bearer #{env.fetch("OPENAI_API_KEY")}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(payload)
        logger.info("Memury structured AI request | capability=#{payload.dig(:text, :format, :name)} | model=#{env.fetch("MEMURY_AI_MODEL")} | store=false")
        http.start { |client| client.request(request) }
      end

      def parse_response(response, schema:, metadata:)
        body = response.body.to_s
        raise Error.new("http #{response.code}", category: "http_#{response.code}", metadata:) unless response.is_a?(Net::HTTPSuccess)
        raise Error.new("empty response", category: "empty_response", metadata:) if body.blank?

        payload = JSON.parse(body)
        request_id = response["x-request-id"].presence || (payload["id"].presence if payload.is_a?(Hash))
        token_usage = safe_token_usage(payload) if payload.is_a?(Hash)
        metadata.merge!(
          "request_id" => request_id,
          "token_usage" => token_usage
        ).compact!
        assert_envelope!(payload, metadata:)
        text = extract_output_text(payload)
        raise Error.new("empty output text", category: "empty_output", metadata:) if text.blank?

        candidate = parse_json_object(text, metadata:)
        validate_schema!(candidate, schema:, metadata:)
        candidate
      end

      def assert_envelope!(payload, metadata:)
        raise Error.new("invalid response envelope", category: "invalid_envelope", metadata:) unless payload.is_a?(Hash)
        raise Error.new("response incomplete", category: "incomplete_response", metadata:) unless payload["status"].to_s == "completed"
        raise Error.new("response incomplete", category: "incomplete_response", metadata:) if payload["incomplete_details"].present?
        raise Error.new("response error", category: "provider_error", metadata:) if payload["error"].present?

        output = payload["output"]
        if payload.key?("output_text") && !payload["output_text"].is_a?(String)
          raise Error.new("empty output text", category: "empty_output_text", metadata:)
        end
        return if payload["output_text"].is_a?(String) && output.blank?
        raise Error.new("empty output", category: "empty_output", metadata:) unless output.is_a?(Array) && output.any?

        output.each do |item|
          unless item.is_a?(Hash) && item["type"].to_s == "message" && item["status"].to_s == "completed"
            raise Error.new("invalid output item", category: "invalid_output", metadata:)
          end

          content = item["content"]
          unless content.is_a?(Array) && content.any?
            raise Error.new("empty content", category: "empty_content", metadata:)
          end

          content.each do |part|
            type = part["type"].to_s
            raise Error.new("refusal received", category: "refusal", metadata:) if type == "refusal"
            raise Error.new("unsupported content type", category: "unsupported_content_type", metadata:) unless type == "output_text"
            raise Error.new("empty output text", category: "empty_output_text", metadata:) unless part["text"].is_a?(String) && part["text"].present?
          end
        end
      end

      def extract_output_text(payload)
        return payload["output_text"].to_s.strip if payload["output_text"].is_a?(String) && payload["output_text"].present?

        Array(payload["output"]).each do |item|
          Array(item["content"]).each do |part|
            return part["text"].to_s.strip if part["type"].to_s == "output_text" && part["text"].to_s.present?
          end
        end
        nil
      end

      def parse_json_object(text, metadata)
        cleaned = text.to_s.strip.sub(/\A```json\s*/i, "").sub(/\A```\s*/, "").sub(/```\s*\z/, "")
        start_index = cleaned.index("{")
        end_index = cleaned.rindex("}")
        raise Error.new("invalid JSON", category: "invalid_json", metadata:) unless start_index && end_index && end_index > start_index

        JSON.parse(cleaned[start_index..end_index])
      end

      def validate_schema!(candidate, schema:, metadata:)
        raise Error.new("schema validation failed", category: "schema_validation_failed", metadata:) unless candidate.is_a?(Hash)

        # JSONSchemer is already a dependency of Canvas and is the local
        # second line of defense after the provider's strict schema contract.
        errors = JSONSchemer.schema(schema).validate(candidate).to_a
        raise Error.new("schema validation failed", category: "schema_validation_failed", metadata:) if errors.any?
      end

      def safe_token_usage(payload)
        usage = payload["usage"]
        return nil unless usage.is_a?(Hash)

        usage.slice("input_tokens", "output_tokens", "total_tokens", "prompt_tokens", "completion_tokens")
             .select { |_key, value| value.is_a?(Numeric) }
             .presence
      end

      def structured_error(category, message, metadata:, started_at:)
        metadata = metadata.to_h.merge("latency_ms" => elapsed_ms(started_at), "status" => "failure", "error_category" => category).compact
        Error.new(message, category:, metadata:)
      end

      def integer_env(name, default)
        Integer(env.fetch(name, default))
      rescue ArgumentError, TypeError
        default
      end

      def elapsed_ms(started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      end
    end
  end
end
