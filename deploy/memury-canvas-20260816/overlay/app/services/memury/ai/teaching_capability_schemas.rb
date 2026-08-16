# frozen_string_literal: true

module Memury
  module Ai
    # Strict, capability-specific schemas for the provider-neutral teaching
    # protocol. Every remote result is validated again locally before it can
    # cross into a typed value object.
    module TeachingCapabilitySchemas
      VERSION = "memury-teaching-capabilities.v1"

      GUIDE = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[level hint contains_direct_answer misconception next_step confidence],
        "properties" => {
          "level" => { "type" => "integer", "minimum" => 1, "maximum" => 4 },
          "hint" => { "type" => "string", "minLength" => 1, "maxLength" => 260 },
          "contains_direct_answer" => { "type" => "boolean" },
          "misconception" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "next_step" => { "type" => "string", "minLength" => 1, "maxLength" => 180 },
          "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
        }
      }.freeze

      PRACTICE = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[prompt knowledge_point difficulty expected_answer explanation question_type source_basis],
        "properties" => {
          "prompt" => { "type" => "string", "minLength" => 8, "maxLength" => 360 },
          "knowledge_point" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "difficulty" => { "type" => "string", "enum" => %w[transfer application analysis] },
          "expected_answer" => { "type" => "string", "minLength" => 1, "maxLength" => 500 },
          "explanation" => { "type" => "string", "minLength" => 1, "maxLength" => 300 },
          "question_type" => { "type" => "string", "enum" => %w[short_answer multiple_choice scenario] },
          "source_basis" => { "type" => "string", "minLength" => 1, "maxLength" => 240 }
        }
      }.freeze

      VALIDATION = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[
          verified
          knowledge_point_match
          difficulty_fit
          self_consistent
          answer_correct
          explanation_consistent
          answer_leak
          transfer_suitable
          validation_basis
          failure_reason_codes
          confidence
          summary
        ],
        "properties" => {
          "verified" => { "type" => "boolean" },
          "knowledge_point_match" => { "type" => "boolean" },
          "difficulty_fit" => { "type" => "boolean" },
          "self_consistent" => { "type" => "boolean" },
          "answer_correct" => { "type" => "boolean" },
          "explanation_consistent" => { "type" => "boolean" },
          "answer_leak" => { "type" => "boolean" },
          "transfer_suitable" => { "type" => "boolean" },
          "validation_basis" => {
            "type" => "string",
            "enum" => %w[trusted_course_source deterministic_rule independent_model_validation insufficient_basis legacy_demo_signal]
          },
          "failure_reason_codes" => {
            "type" => "array",
            "maxItems" => 5,
            "items" => { "type" => "string", "minLength" => 1, "maxLength" => 80 }
          },
          "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 },
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 300 }
        }
      }.freeze

      TRANSFER = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[
          passed
          independently_completed
          hint_dependent
          misconception_tags
          scoring_basis
          mastery_delta_suggestion
          confidence
          reason_code
          validation_basis
          summary
        ],
        "properties" => {
          "passed" => { "type" => "boolean" },
          "independently_completed" => { "type" => "boolean" },
          "hint_dependent" => { "type" => "boolean" },
          "misconception_tags" => {
            "type" => "array",
            "maxItems" => 5,
            "items" => { "type" => "string", "minLength" => 1, "maxLength" => 80 }
          },
          "scoring_basis" => { "type" => "string", "minLength" => 1, "maxLength" => 260 },
          "mastery_delta_suggestion" => { "type" => "number", "minimum" => -0.25, "maximum" => 0.25 },
          "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 },
          "reason_code" => { "type" => "string", "minLength" => 1, "maxLength" => 80 },
          "validation_basis" => {
            "type" => "string",
            "enum" => %w[trusted_course_source deterministic_rule independent_model_validation insufficient_basis legacy_demo_signal]
          },
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 300 }
        }
      }.freeze

      EVIDENCE_SUMMARY = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[
          verified_conclusions
          unresolved_misconceptions
          hint_dependence
          transfer_result
          evidence_strength
          planner_summary
          confidence
        ],
        "properties" => {
          "verified_conclusions" => { "type" => "array", "maxItems" => 5, "items" => { "type" => "string", "maxLength" => 180 } },
          "unresolved_misconceptions" => { "type" => "array", "maxItems" => 5, "items" => { "type" => "string", "maxLength" => 120 } },
          "hint_dependence" => { "type" => "string", "enum" => %w[none low medium high unknown] },
          "transfer_result" => { "type" => "string", "enum" => %w[passed failed not_attempted] },
          "evidence_strength" => { "type" => "string", "enum" => %w[weak moderate strong] },
          "planner_summary" => { "type" => "string", "minLength" => 1, "maxLength" => 280 },
          "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
        }
      }.freeze

      Q_GRAPH_REPLY = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[answer follow_up conversation_summary key_points],
        "properties" => {
          "answer" => { "type" => "string", "minLength" => 1, "maxLength" => 700 },
          "follow_up" => { "type" => "string", "minLength" => 1, "maxLength" => 220 },
          "conversation_summary" => { "type" => "string", "minLength" => 1, "maxLength" => 500 },
          "key_points" => {
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 5,
            "items" => { "type" => "string", "minLength" => 1, "maxLength" => 180 }
          }
        }
      }.freeze

      SCHEMAS = {
        "guide" => GUIDE,
        "generate_practice" => PRACTICE,
        "validate_practice" => VALIDATION,
        "assess_transfer" => TRANSFER,
        "summarize_evidence" => EVIDENCE_SUMMARY,
        "q_graph_reply" => Q_GRAPH_REPLY
      }.freeze

      class << self
        def schema(capability)
          SCHEMAS.fetch(capability.to_s)
        end
      end
    end
  end
end
