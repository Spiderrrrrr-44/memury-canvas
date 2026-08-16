# frozen_string_literal: true

module Memury
  module Teaching
    # Namespace marker for this intentionally compact protocol value-object
    # file; the concrete types remain directly under Memury::Teaching.
    module Protocol; end

    # Typed, provider-neutral value objects shared by the orchestration layer.
    # They intentionally contain only structured teaching evidence; provider
    # prompts, raw responses, and private reasoning never cross this boundary.
    class Diagnosis
      ATTRIBUTES = %i[
        diagnosis_summary
        answer_judgment
        misconception_type
        evidence
        confidence
        verification_question
        hint
        transfer_question
        learner_state_suggestion
        source
        fallback_reason
        compatibility_note
        latency_ms
        metadata
      ].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(**attributes)
        ATTRIBUTES.each { |attribute| instance_variable_set("@#{attribute}", attributes[attribute]) }
        freeze
      end

      def self.from_result(result)
        diagnostic = result.diagnostic.deep_stringify_keys
        new(
          diagnosis_summary: diagnostic.fetch("diagnosis_summary"),
          answer_judgment: diagnostic.fetch("answer_judgment"),
          misconception_type: diagnostic.fetch("misconception_type"),
          evidence: Array(diagnostic.fetch("evidence")),
          confidence: diagnostic.fetch("confidence").to_f,
          verification_question: diagnostic.fetch("verification_question"),
          hint: diagnostic.fetch("hint"),
          transfer_question: diagnostic.fetch("transfer_question"),
          learner_state_suggestion: diagnostic.fetch("learner_state_suggestion"),
          source: result.source.to_s,
          fallback_reason: result.fallback_reason,
          compatibility_note: result.compatibility_note,
          latency_ms: result.latency_ms,
          metadata: result.respond_to?(:metadata) ? result.metadata : nil
        )
      end

      def to_h
        {
          "diagnosis_summary" => diagnosis_summary,
          "answer_judgment" => answer_judgment,
          "misconception_type" => misconception_type,
          "evidence" => evidence,
          "confidence" => confidence,
          "verification_question" => verification_question,
          "hint" => hint,
          "transfer_question" => transfer_question,
          "learner_state_suggestion" => learner_state_suggestion,
          "source" => source,
          "fallback_reason" => fallback_reason,
          "compatibility_note" => compatibility_note,
          "latency_ms" => latency_ms,
          "metadata" => metadata
        }.compact
      end
    end

    class Guidance
      attr_reader :level, :layers, :contains_direct_answer, :misconception, :next_step, :confidence, :source, :metadata

      def initialize(layers:,
                     source:,
                     level: nil,
                     contains_direct_answer: false,
                     misconception: nil,
                     next_step: nil,
                     confidence: 0.0,
                     metadata: nil)
        @level = level.to_i if level
        @layers = Array(layers).map(&:to_s).compact_blank.first(4).freeze
        @contains_direct_answer = !!contains_direct_answer
        @misconception = misconception.to_s.presence
        @next_step = next_step.to_s.presence
        @confidence = confidence.to_f.clamp(0.0, 1.0)
        @source = source.to_s.freeze
        @metadata = metadata
        freeze
      end

      def to_h
        {
          "level" => level,
          "layers" => layers,
          "contains_direct_answer" => contains_direct_answer,
          "misconception" => misconception,
          "next_step" => next_step,
          "confidence" => confidence,
          "source" => source,
          "metadata" => metadata
        }.compact
      end
    end

    class PracticeCandidate
      attr_reader :id,
                  :prompt,
                  :expected_answer,
                  :explanation,
                  :knowledge_point,
                  :difficulty,
                  :question_type,
                  :source_basis,
                  :source,
                  :metadata

      def initialize(id:,
                     prompt:,
                     expected_answer:,
                     explanation:,
                     knowledge_point:,
                     difficulty:,
                     source:,
                     question_type: "short_answer",
                     source_basis: nil,
                     metadata: nil)
        @id = id.to_s
        @prompt = prompt.to_s
        @expected_answer = expected_answer.to_s
        @explanation = explanation.to_s
        @knowledge_point = knowledge_point.to_s
        @difficulty = difficulty.to_s
        @question_type = question_type.to_s
        @source_basis = source_basis.to_s.presence
        @source = source.to_s
        @metadata = metadata
        freeze
      end

      # The answer is server-side only. Callers that cross the public state
      # boundary must use #public_h instead.
      def to_h
        {
          "id" => id,
          "prompt" => prompt,
          "expected_answer" => expected_answer,
          "explanation" => explanation,
          "knowledge_point" => knowledge_point,
          "difficulty" => difficulty,
          "question_type" => question_type,
          "source_basis" => source_basis,
          "source" => source,
          "metadata" => metadata
        }
      end

      def public_h
        to_h.except("expected_answer", "explanation", "metadata")
      end
    end

    class ValidationResult
      attr_reader :status,
                  :verified,
                  :confidence,
                  :reason_code,
                  :summary,
                  :source,
                  :validation_basis,
                  :knowledge_point_match,
                  :difficulty_fit,
                  :self_consistent,
                  :answer_correct,
                  :explanation_consistent,
                  :answer_leak,
                  :transfer_suitable,
                  :independent_completed,
                  :hint_dependent,
                  :misconception_tags,
                  :scoring_basis,
                  :mastery_delta_suggestion,
                  :metadata

      def initialize(status:,
                     verified:,
                     confidence:,
                     reason_code:,
                     summary:,
                     source:,
                     validation_basis: "insufficient_basis",
                     knowledge_point_match: nil,
                     difficulty_fit: nil,
                     self_consistent: nil,
                     answer_correct: nil,
                     explanation_consistent: nil,
                     answer_leak: nil,
                     transfer_suitable: nil,
                     independent_completed: nil,
                     hint_dependent: nil,
                     misconception_tags: [],
                     scoring_basis: nil,
                     mastery_delta_suggestion: 0.0,
                     metadata: nil)
        @status = status.to_s
        @verified = !!verified
        @confidence = confidence.to_f.clamp(0.0, 1.0)
        @reason_code = reason_code.to_s
        @summary = summary.to_s
        @source = source.to_s
        @validation_basis = validation_basis.to_s
        @knowledge_point_match = knowledge_point_match
        @difficulty_fit = difficulty_fit
        @self_consistent = self_consistent
        @answer_correct = answer_correct
        @explanation_consistent = explanation_consistent
        @answer_leak = answer_leak
        @transfer_suitable = transfer_suitable
        @independent_completed = independent_completed
        @hint_dependent = hint_dependent
        @misconception_tags = Array(misconception_tags).map(&:to_s).first(5).freeze
        @scoring_basis = scoring_basis.to_s.presence
        @mastery_delta_suggestion = mastery_delta_suggestion.to_f.clamp(-0.25, 0.25)
        @metadata = metadata
        freeze
      end

      def completed?
        %w[passed failed].include?(status)
      end

      def to_h
        {
          "status" => status,
          "verified" => verified,
          "confidence" => confidence,
          "reason_code" => reason_code,
          "summary" => summary,
          "source" => source,
          "validation_basis" => validation_basis,
          "knowledge_point_match" => knowledge_point_match,
          "difficulty_fit" => difficulty_fit,
          "self_consistent" => self_consistent,
          "answer_correct" => answer_correct,
          "explanation_consistent" => explanation_consistent,
          "answer_leak" => answer_leak,
          "transfer_suitable" => transfer_suitable,
          "independent_completed" => independent_completed,
          "hint_dependent" => hint_dependent,
          "misconception_tags" => misconception_tags,
          "scoring_basis" => scoring_basis,
          "mastery_delta_suggestion" => mastery_delta_suggestion,
          "metadata" => metadata
        }
      end
    end

    class EvidenceSummary
      attr_reader :summary,
                  :verified_count,
                  :total_count,
                  :confidence,
                  :source,
                  :verified_conclusions,
                  :unresolved_misconceptions,
                  :hint_dependence,
                  :transfer_result,
                  :evidence_strength,
                  :planner_summary,
                  :metadata

      def initialize(summary:,
                     verified_count:,
                     total_count:,
                     confidence:,
                     source:,
                     verified_conclusions: [],
                     unresolved_misconceptions: [],
                     hint_dependence: "unknown",
                     transfer_result: "not_attempted",
                     evidence_strength: "weak",
                     planner_summary: nil,
                     metadata: nil)
        @summary = summary.to_s
        @verified_count = verified_count.to_i
        @total_count = total_count.to_i
        @confidence = confidence.to_f.clamp(0.0, 1.0)
        @source = source.to_s
        @verified_conclusions = Array(verified_conclusions).map(&:to_s).first(5).freeze
        @unresolved_misconceptions = Array(unresolved_misconceptions).map(&:to_s).first(5).freeze
        @hint_dependence = hint_dependence.to_s
        @transfer_result = transfer_result.to_s
        @evidence_strength = evidence_strength.to_s
        @planner_summary = planner_summary.to_s.presence
        @metadata = metadata
        freeze
      end

      def to_h
        {
          "summary" => summary,
          "verified_count" => verified_count,
          "total_count" => total_count,
          "confidence" => confidence,
          "source" => source,
          "verified_conclusions" => verified_conclusions,
          "unresolved_misconceptions" => unresolved_misconceptions,
          "hint_dependence" => hint_dependence,
          "transfer_result" => transfer_result,
          "evidence_strength" => evidence_strength,
          "planner_summary" => planner_summary,
          "metadata" => metadata
        }
      end
    end

    # Small structural contract. Providers may be Ruby classes or adapters to
    # a remote model; orchestration code depends only on these methods.
    module Provider
      def diagnose(context)
        raise NotImplementedError
      end

      def guide(context)
        raise NotImplementedError
      end

      def generate_practice(context)
        raise NotImplementedError
      end

      def validate_practice(context)
        raise NotImplementedError
      end

      def assess_transfer(context)
        raise NotImplementedError
      end

      def summarize_evidence(context)
        raise NotImplementedError
      end
    end
  end
end
