# frozen_string_literal: true

require "digest"
require_relative "../ai/structured_response_client"
require_relative "../ai/teaching_capability_schemas"
require_relative "protocol"
require_relative "contexts"
require_relative "deterministic_provider"

module Memury
  module Teaching
    # Provider implementation with one shared Responses API transport and a
    # separate role/schema/context for each teaching capability.
    class OpenAiProvider
      include Provider

      def initialize(diagnosis_service: Memury::Ai::TeachingDiagnosisService,
                     client: Memury::Ai::StructuredResponseClient.new,
                     fallback: DeterministicProvider.new)
        @diagnosis_service = diagnosis_service
        @client = client
        @fallback = fallback
      end

      def diagnose(context)
        result = diagnosis_service.call(**context.to_h.slice(
          "course_or_subject", "knowledge_point", "question", "scoring_basis", "student_answer", "learner_state_summary"
        ).symbolize_keys)
        Diagnosis.from_result(result)
      end

      def guide(context)
        result = client.call(
          capability: "guide",
          instructions: <<~TEXT,
            You are Memury's Socratic tutor. Give one progressive hint for the
            observed misconception. Never provide the final answer. Return
            only the requested JSON object.
          TEXT
          input: context.to_h.slice(
            "course_or_subject",
            "knowledge_point",
            "question",
            "student_answer",
            "learner_state_summary",
            "recent_misconceptions",
            "course_materials",
            "diagnosis"
          ),
          schema: Memury::Ai::TeachingCapabilitySchemas::GUIDE,
          schema_version: Memury::Ai::TeachingCapabilitySchemas::VERSION
        )
        data = result.data
        Guidance.new(
          level: data.fetch("level"),
          layers: [data.fetch("hint")],
          contains_direct_answer: data.fetch("contains_direct_answer"),
          misconception: data.fetch("misconception"),
          next_step: data.fetch("next_step"),
          confidence: data.fetch("confidence"),
          source: "openai",
          metadata: result.metadata
        )
      rescue Memury::Ai::StructuredResponseClient::Error => e
        fallback_with_reason(fallback.guide(context), e)
      end

      def generate_practice(context)
        result = client.call(
          capability: "generate_practice",
          instructions: <<~TEXT,
            You are Memury's transfer-practice generator. Generate one new
            scenario that tests the same knowledge point without copying the
            original wording. Return a concise answer key and explanation in
            the requested JSON only. Do not include private reasoning.
          TEXT
          input: context.to_h,
          schema: Memury::Ai::TeachingCapabilitySchemas::PRACTICE,
          schema_version: Memury::Ai::TeachingCapabilitySchemas::VERSION
        )
        data = result.data
        PracticeCandidate.new(
          id: "practice-#{Digest::SHA256.hexdigest(data.fetch("prompt"))[0, 12]}",
          prompt: data.fetch("prompt"),
          expected_answer: data.fetch("expected_answer"),
          explanation: data.fetch("explanation"),
          knowledge_point: data.fetch("knowledge_point"),
          difficulty: data.fetch("difficulty"),
          question_type: data.fetch("question_type"),
          source_basis: data.fetch("source_basis"),
          source: "openai",
          metadata: result.metadata
        )
      rescue Memury::Ai::StructuredResponseClient::Error => e
        fallback_with_reason(fallback.generate_practice(context), e)
      end

      def validate_practice(context)
        return insufficient_basis_result unless trusted_basis?(context)

        result = client.call(
          capability: "validate_practice",
          instructions: <<~TEXT,
            You are an independent validator, not the generator. Check the
            candidate question, answer and explanation against the trusted
            course basis. Do not accept the candidate's claims or any hidden
            mastery statement. Return only the strict validation JSON.
          TEXT
          input: context.to_h,
          schema: Memury::Ai::TeachingCapabilitySchemas::VALIDATION,
          schema_version: Memury::Ai::TeachingCapabilitySchemas::VERSION
        )
        validation_from_ai(result.data, result.metadata)
      rescue Memury::Ai::StructuredResponseClient::Error => e
        # Never validate an AI-generated candidate with the deterministic
        # validator after the independent validator transport failed. That
        # would turn an unverified model claim into verified evidence. The
        # orchestration layer discards this candidate and requests a
        # deterministic template with a deterministic reference rule.
        validator_unavailable_result(e)
      end

      def assess_transfer(context)
        if context.student_answer.to_s.strip.blank?
          return legacy_signal_result(context) unless context.legacy_correct.nil?

          return missing_transfer_answer_result
        end
        return insufficient_basis_result if context.reference_answer.to_s.strip.blank? && context.candidate_expected_answer.to_s.strip.blank?

        result = client.call(
          capability: "assess_transfer",
          instructions: <<~TEXT,
            You are an independent transfer assessor. Evaluate the student's
            answer against the candidate and trusted reference standard. Do
            not trust client-side correctness flags. Report bounded mastery
            delta advice only; the deterministic planner makes the final update.
            Return only the strict JSON object.
          TEXT
          input: context.to_h.except("legacy_correct"),
          schema: Memury::Ai::TeachingCapabilitySchemas::TRANSFER,
          schema_version: Memury::Ai::TeachingCapabilitySchemas::VERSION
        )
        transfer_from_ai(result.data, result.metadata)
      rescue Memury::Ai::StructuredResponseClient::Error => e
        fallback_with_reason(fallback.assess_transfer(context), e)
      end

      def summarize_evidence(context)
        evidence = evidence_input(context)
        return fallback_with_reason(fallback.summarize_evidence(context), "invalid_evidence_context") if evidence.nil?

        result = client.call(
          capability: "summarize_evidence",
          instructions: <<~TEXT,
            You are Memury's evidence summarizer. Read only the supplied
            structured evidence. Do not infer from prompts, raw model output,
            private reasoning or unsupported mastery claims. Return a minimal
            planner-safe JSON summary.
          TEXT
          input: { "evidence" => evidence },
          schema: Memury::Ai::TeachingCapabilitySchemas::EVIDENCE_SUMMARY,
          schema_version: Memury::Ai::TeachingCapabilitySchemas::VERSION
        )
        data = result.data
        EvidenceSummary.new(
          summary: data.fetch("planner_summary"),
          verified_count: evidence.count { |item| item["verified"] == true },
          total_count: evidence.length,
          confidence: data.fetch("confidence"),
          source: "openai",
          verified_conclusions: data.fetch("verified_conclusions"),
          unresolved_misconceptions: data.fetch("unresolved_misconceptions"),
          hint_dependence: data.fetch("hint_dependence"),
          transfer_result: data.fetch("transfer_result"),
          evidence_strength: data.fetch("evidence_strength"),
          planner_summary: data.fetch("planner_summary"),
          metadata: result.metadata
        )
      rescue Memury::Ai::StructuredResponseClient::Error => e
        fallback_with_reason(fallback.summarize_evidence(context), e)
      end

      private

      attr_reader :diagnosis_service, :client, :fallback

      def trusted_basis?(context)
        context.source_materials.present? || context.reference_answer.to_s.strip.present?
      end

      def insufficient_basis_result
        ValidationResult.new(
          status: "failed",
          verified: false,
          confidence: 0.0,
          reason_code: "insufficient_validation_basis",
          summary: "缺少可信课程依据或确定性参考标准，不能验证迁移题。",
          source: "insufficient_basis",
          validation_basis: "insufficient_basis",
          metadata: { "provider" => "insufficient_basis", "status" => "blocked" }
        )
      end

      def legacy_signal_result(_context)
        ValidationResult.new(
          status: "failed",
          verified: false,
          confidence: 0.0,
          reason_code: "legacy_demo_signal",
          summary: "只收到旧版 correct 信号，没有可验证的学生答案。",
          source: "legacy_demo_signal",
          validation_basis: "legacy_demo_signal",
          independent_completed: false,
          metadata: { "provider" => "legacy_demo_signal", "status" => "blocked" }
        )
      end

      def missing_transfer_answer_result
        ValidationResult.new(
          status: "failed",
          verified: false,
          confidence: 0.0,
          reason_code: "missing_transfer_answer",
          summary: "没有收到可验证的迁移题答案。",
          source: "insufficient_basis",
          validation_basis: "insufficient_basis",
          metadata: { "provider" => "insufficient_basis", "status" => "blocked" }
        )
      end

      def validator_unavailable_result(error)
        reason = error.respond_to?(:category) ? error.category : error.to_s
        ValidationResult.new(
          status: "failed",
          verified: false,
          confidence: 0.0,
          reason_code: "validator_unavailable",
          summary: "独立验证器不可用，候选题未被采纳。",
          source: "deterministic_fallback",
          validation_basis: "insufficient_basis",
          metadata: {
            "provider" => "deterministic_fallback",
            "status" => "fallback",
            "fallback_reason" => reason,
            "error_category" => reason
          }
        )
      end

      def validation_from_ai(data, metadata)
        all_checks = %w[knowledge_point_match difficulty_fit self_consistent answer_correct explanation_consistent transfer_suitable].all? { |key| data[key] == true }
        verified = data["verified"] == true && all_checks && data["answer_leak"] == false &&
                   !%w[insufficient_basis legacy_demo_signal].include?(data["validation_basis"])
        ValidationResult.new(
          status: verified ? "passed" : "failed",
          verified:,
          confidence: data.fetch("confidence"),
          reason_code: verified ? "candidate_validated" : Array(data["failure_reason_codes"]).first.presence || "validator_rejected",
          summary: data.fetch("summary"),
          source: "openai",
          validation_basis: data.fetch("validation_basis"),
          knowledge_point_match: data.fetch("knowledge_point_match"),
          difficulty_fit: data.fetch("difficulty_fit"),
          self_consistent: data.fetch("self_consistent"),
          answer_correct: data.fetch("answer_correct"),
          explanation_consistent: data.fetch("explanation_consistent"),
          answer_leak: data.fetch("answer_leak"),
          transfer_suitable: data.fetch("transfer_suitable"),
          metadata:
        )
      end

      def transfer_from_ai(data, metadata)
        verified = data["passed"] == true && data["independently_completed"] == true && !data["hint_dependent"] &&
                   data["validation_basis"] != "legacy_demo_signal" && data["validation_basis"] != "insufficient_basis"
        ValidationResult.new(
          status: verified ? "passed" : "failed",
          verified:,
          confidence: data.fetch("confidence"),
          reason_code: verified ? data.fetch("reason_code") : "transfer_not_independently_verified",
          summary: data.fetch("summary"),
          source: "openai",
          validation_basis: data.fetch("validation_basis"),
          independent_completed: data.fetch("independently_completed"),
          hint_dependent: data.fetch("hint_dependent"),
          misconception_tags: data.fetch("misconception_tags"),
          scoring_basis: data.fetch("scoring_basis"),
          mastery_delta_suggestion: data.fetch("mastery_delta_suggestion"),
          metadata:
        )
      end

      def evidence_input(context)
        evidence = if context.respond_to?(:evidence)
                     context.evidence
                   elsif context.respond_to?(:fetch)
                     context.fetch(:evidence, context["evidence"] || [])
                   end
        return nil unless evidence.is_a?(Array)

        evidence.first(20).map do |item|
          item = item.stringify_keys
          {
            "kind" => item["kind"],
            "verified" => item["verified"] == true,
            "confidence" => item["confidence"],
            "validation_basis" => item["validation_basis"],
            "payload" => item.fetch("payload", {}).to_h.slice("answer_judgment", "misconception_type", "reason_code", "summary", "verified")
          }.compact
        end
      end

      def fallback_with_reason(result, error)
        reason = error.respond_to?(:category) ? error.category : error.to_s
        metadata = result.metadata.to_h.merge(error.respond_to?(:metadata) ? error.metadata.to_h : {}).merge(
          "provider" => "deterministic_fallback",
          "status" => "fallback",
          "fallback_reason" => reason,
          "error_category" => reason
        )
        case result
        when Guidance
          Guidance.new(level: result.level,
                       layers: result.layers,
                       contains_direct_answer: result.contains_direct_answer,
                       misconception: result.misconception,
                       next_step: result.next_step,
                       confidence: result.confidence,
                       source: "deterministic_fallback",
                       metadata:)
        when PracticeCandidate
          source = (result.source == "deterministic_template") ? "deterministic_template" : "deterministic_fallback"
          PracticeCandidate.new(id: result.id,
                                prompt: result.prompt,
                                expected_answer: result.expected_answer,
                                explanation: result.explanation,
                                knowledge_point: result.knowledge_point,
                                difficulty: result.difficulty,
                                question_type: result.question_type,
                                source_basis: result.source_basis,
                                source:,
                                metadata:)
        when ValidationResult
          ValidationResult.new(status: result.status,
                               verified: result.verified,
                               confidence: result.confidence,
                               reason_code: result.reason_code,
                               summary: result.summary,
                               source: "deterministic_fallback",
                               validation_basis: result.validation_basis,
                               knowledge_point_match: result.knowledge_point_match,
                               difficulty_fit: result.difficulty_fit,
                               self_consistent: result.self_consistent,
                               answer_correct: result.answer_correct,
                               explanation_consistent: result.explanation_consistent,
                               answer_leak: result.answer_leak,
                               transfer_suitable: result.transfer_suitable,
                               independent_completed: result.independent_completed,
                               hint_dependent: result.hint_dependent,
                               misconception_tags: result.misconception_tags,
                               scoring_basis: result.scoring_basis,
                               mastery_delta_suggestion: result.mastery_delta_suggestion,
                               metadata:)
        when EvidenceSummary
          EvidenceSummary.new(summary: result.summary,
                              verified_count: result.verified_count,
                              total_count: result.total_count,
                              confidence: result.confidence,
                              source: "deterministic_fallback",
                              verified_conclusions: result.verified_conclusions,
                              unresolved_misconceptions: result.unresolved_misconceptions,
                              hint_dependence: result.hint_dependence,
                              transfer_result: result.transfer_result,
                              evidence_strength: result.evidence_strength,
                              planner_summary: result.planner_summary,
                              metadata:)
        else
          result
        end
      end
    end
  end
end
