# frozen_string_literal: true

require "json_schemer"

module Memury
  module Ai
    module TeachingDiagnosisSchema
      MISCONCEPTION_TYPES = %w[
        conceptual
        procedural
        calculation
        incomplete
        guessing
        insufficient_evidence
      ].freeze

      ANSWER_JUDGMENTS = %w[
        correct
        incorrect
        uncertain
      ].freeze

      CANONICAL_SCHEMA = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => [
          "diagnosis_summary",
          "answer_judgment",
          "misconception_type",
          "evidence",
          "confidence",
          "verification_question",
          "hint",
          "transfer_question",
          "learner_state_suggestion"
        ],
        "properties" => {
          "diagnosis_summary" => {
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 180,
            "description" => "Summarize the student's observed answer evidence and the concept gap without quoting or paraphrasing the reference answer."
          },
          "answer_judgment" => {
            "type" => "string",
            "enum" => ANSWER_JUDGMENTS
          },
          "misconception_type" => {
            "type" => "string",
            "enum" => MISCONCEPTION_TYPES
          },
          "evidence" => {
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 3,
            "items" => {
              "type" => "string",
              "minLength" => 1,
              "maxLength" => 120
            }
          },
          "confidence" => {
            "type" => "number",
            "minimum" => 0,
            "maximum" => 1
          },
          "verification_question" => {
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 220,
            "description" => "Ask a follow-up question that re-tests the concept without revealing the answer."
          },
          "hint" => {
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 240,
            "description" => "Give a progressive clue that supports reasoning but does not give away the answer."
          },
          "transfer_question" => {
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 240,
            "description" => "Change the context or surface form while testing the same concept; do not repeat the answer."
          },
          "learner_state_suggestion" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[skill suggested_status reason],
            "properties" => {
              "skill" => {
                "type" => "string",
                "minLength" => 1,
                "maxLength" => 100
              },
              "suggested_status" => {
                "type" => "string",
                "minLength" => 1,
                "maxLength" => 60
              },
              "reason" => {
                "type" => "string",
                "minLength" => 1,
                "maxLength" => 180,
                "description" => "Explain the suggestion using student evidence and concept observations only."
              }
            }
          }
        }
      }.freeze

      class << self
        def canonical_schema
          CANONICAL_SCHEMA
        end

        def provider_schema
          CANONICAL_SCHEMA
        end

        def validator
          VALIDATOR
        end
      end

      VALIDATOR = JSONSchemer.schema(CANONICAL_SCHEMA)
    end
  end
end
