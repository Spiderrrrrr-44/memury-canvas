# frozen_string_literal: true

require "set"

module Memury
  class PublicStateSerializer
    SENSITIVE_KEYS = [
      "reference_answer",
      "referenceAnswer",
      "standard_answer",
      "standardAnswer",
      "correct_answer",
      "correctAnswer",
      "expected_answer",
      "expectedAnswer",
      "model_answer",
      "modelAnswer",
      "answer_key",
      "answerKey",
      "provider_prompt",
      "providerPrompt",
      "provider_raw_body",
      "providerRawBody",
      "provider_response",
      "providerResponse",
      "provider_response_body",
      "providerResponseBody",
      "provider_response_text",
      "providerResponseText",
      "raw_response",
      "rawResponse",
      "raw_body",
      "rawBody",
      "raw_provider_body",
      "rawProviderBody",
      "raw_prompt",
      "rawPrompt",
      "prompt",
      "exception_backtrace",
      "exceptionBacktrace",
      "backtrace",
      "stack_trace",
      "stackTrace",
      "authorization"
    ].to_set.freeze

    class << self
      def call(state)
        new(state).call
      end
    end

    def initialize(state)
      @state = state
    end

    def call
      sanitize(state)
    end

    private

    attr_reader :state

    def sanitize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          next if sensitive_key?(key)

          result[key] = sanitize(nested)
        end
      when Array
        value.map { |nested| sanitize(nested) }
      else
        value
      end
    end

    def sensitive_key?(key)
      return true if SENSITIVE_KEYS.include?(key.to_s)

      reference_alias_key?(key)
    end

    def reference_alias_key?(key)
      key.to_s.match?(/\A(?:reference|standard|correct|expected|model)_?(?:answer|response)\z/i) ||
        key.to_s.match?(/\Aanswer_?key\z/i)
    end
  end
end
