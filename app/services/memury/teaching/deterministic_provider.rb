# frozen_string_literal: true

require "digest"
require_relative "protocol"
require_relative "contexts"

module Memury
  module Teaching
    # A complete no-key provider. It is deliberately small and explainable so
    # the demo remains runnable when OpenAI is disabled or unavailable.
    class DeterministicProvider
      include Provider

      def diagnose(context)
        diagnostic = Memury::Ai::TeachingDiagnosisFallback.build(context.to_h)
        Diagnosis.new(
          **diagnostic.symbolize_keys,
          source: "rule_fallback",
          fallback_reason: "deterministic provider",
          compatibility_note: nil,
          latency_ms: 0,
          metadata: {
            "provider" => "deterministic",
            "schema_version" => Memury::Ai::TeachingDiagnosisSchema::VERSION,
            "status" => "fallback",
            "error_category" => "deterministic_provider"
          }
        )
      end

      def guide(context)
        diagnostic = context.respond_to?(:diagnosis) ? context.diagnosis : nil
        diagnostic_hint = if diagnostic.respond_to?(:hint)
                            diagnostic.hint
                          elsif diagnostic.is_a?(Hash)
                            diagnostic["hint"] || diagnostic[:hint]
                          end
        layers = [diagnostic_hint, "先指出题目中的受力对象，再说明每个力作用在哪个对象上。", "最后用一个不同情境复述判断规则。"].compact
        Guidance.new(
          level: 1,
          layers:,
          contains_direct_answer: false,
          misconception: context.recent_misconceptions.first.is_a?(Hash) ? context.recent_misconceptions.first["name"].to_s.presence : "insufficient_evidence",
          next_step: "回答后再用一个不同情境验证迁移。",
          confidence: 0.6,
          source: "deterministic_provider",
          metadata: { "provider" => "deterministic", "status" => "fallback" }
        )
      end

      def generate_practice(context)
        prompt = context.transfer_question.presence ||
                 "换一个情境：#{context.knowledge_point}发生变化时，你会先检查哪些受力对象？"
        expected = context.scoring_basis.presence || "先确认同一物体、作用对象和力的方向，再作出判断。"
        PracticeCandidate.new(
          id: "practice-#{Digest::SHA256.hexdigest(prompt)[0, 12]}",
          prompt:,
          expected_answer: expected,
          explanation: "回答应先识别作用对象，再比较力的关系。",
          knowledge_point: context.knowledge_point,
          difficulty: context.difficulty.presence || "transfer",
          question_type: "scenario",
          source_basis: "deterministic_rule",
          source: "deterministic_template",
          metadata: { "provider" => "deterministic", "status" => "fallback" }
        )
      end

      def validate_practice(context)
        prompt = context.candidate_prompt.to_s.strip
        expected = context.candidate_expected_answer.to_s.strip
        objective = context.knowledge_point.to_s.strip
        if prompt.length < 8 || expected.blank? || objective.blank?
          return ValidationResult.new(
            status: "failed",
            verified: false,
            confidence: 0.0,
            reason_code: "invalid_candidate",
            summary: "迁移题缺少题干、目标或参考标准。",
            source: "deterministic_validator",
            validation_basis: "insufficient_basis",
            metadata: { "provider" => "deterministic", "status" => "failed" }
          )
        end

        leaks_answer = prompt.downcase.include?(expected.downcase) && expected.length >= 8
        if leaks_answer
          return ValidationResult.new(
            status: "failed",
            verified: false,
            confidence: 0.0,
            reason_code: "answer_leak",
            summary: "迁移题题干泄露了参考答案。",
            source: "deterministic_validator",
            validation_basis: "deterministic_rule",
            knowledge_point_match: true,
            difficulty_fit: true,
            self_consistent: true,
            answer_correct: false,
            explanation_consistent: false,
            answer_leak: true,
            transfer_suitable: false,
            metadata: { "provider" => "deterministic", "status" => "failed" }
          )
        end

        ValidationResult.new(
          status: "passed",
          verified: true,
          confidence: 0.9,
          reason_code: "candidate_validated",
          summary: "迁移题覆盖目标知识点且未直接泄露答案。",
          source: "deterministic_validator",
          validation_basis: "deterministic_rule",
          knowledge_point_match: true,
          difficulty_fit: true,
          self_consistent: true,
          answer_correct: true,
          explanation_consistent: true,
          answer_leak: false,
          transfer_suitable: true,
          metadata: { "provider" => "deterministic", "status" => "success" }
        )
      end

      def assess_transfer(context)
        answer = context.student_answer.to_s.strip
        expected = context.candidate_expected_answer.to_s.strip.presence || context.reference_answer.to_s.strip
        if answer.blank? && !context.legacy_correct.nil?
          reason_code = context.legacy_correct ? "legacy_demo_signal" : "legacy_demo_answer_failed"
          return ValidationResult.new(
            status: "failed",
            verified: false,
            confidence: 0.0,
            reason_code:,
            summary: "只收到旧版 correct 信号，没有可验证的学生答案。",
            source: "legacy_demo_signal",
            validation_basis: "legacy_demo_signal",
            independent_completed: false,
            metadata: { "provider" => "legacy_demo_signal", "status" => "blocked" }
          )
        end

        if answer.blank? || expected.blank?
          return ValidationResult.new(
            status: "failed",
            verified: false,
            confidence: 0.1,
            reason_code: "missing_transfer_answer",
            summary: "没有收到可验证的迁移题答案。",
            source: "deterministic_validator",
            validation_basis: "insufficient_basis",
            metadata: { "provider" => "deterministic", "status" => "failed" }
          )
        end

        normalized_answer = normalize(answer)
        keywords = expected.split(/[[:space:][:punct:]]+/).compact_blank.uniq
        matched = keywords.count { |keyword| normalized_answer.include?(normalize(keyword)) }
        passed = keywords.any? && matched.to_f / keywords.length >= 0.6
        ValidationResult.new(
          status: passed ? "passed" : "failed",
          verified: passed,
          confidence: passed ? 0.86 : 0.62,
          reason_code: passed ? "transfer_answer_validated" : "transfer_answer_incomplete",
          summary: passed ? "迁移题答案覆盖关键判断。" : "迁移题答案仍缺少关键判断。",
          source: "deterministic_validator",
          validation_basis: "deterministic_rule",
          independent_completed: true,
          hint_dependent: context.hint_dependent,
          misconception_tags: passed ? [] : ["incomplete_transfer"],
          scoring_basis: expected,
          mastery_delta_suggestion: if passed
                                      context.hint_dependent ? 0.12 : 0.24
                                    else
                                      -0.04
                                    end,
          metadata: { "provider" => "deterministic", "status" => passed ? "success" : "failed" }
        )
      end

      def summarize_evidence(context)
        evidence = if context.respond_to?(:evidence)
                     context.evidence
                   else
                     Array(context.fetch(:evidence, context["evidence"] || []))
                   end
        verified = evidence.count { |item| item["verified"] || item[:verified] }
        confidence = evidence.empty? ? 0.0 : (verified.to_f / evidence.length).round(2)
        EvidenceSummary.new(
          summary: "#{verified}/#{evidence.length} 条学习证据已通过验证。",
          verified_count: verified,
          total_count: evidence.length,
          confidence:,
          source: "deterministic_provider",
          verified_conclusions: evidence.filter_map do |item|
            next unless item["verified"] || item[:verified]

            item["summary"] || item[:summary]
          end,
          unresolved_misconceptions: evidence.filter_map do |item|
            next if item["verified"] || item[:verified]

            item["misconception_type"] || item[:misconception_type]
          end,
          hint_dependence: (evidence.any? { |item| item["hint_dependent"] || item[:hint_dependent] }) ? "medium" : "none",
          transfer_result: (evidence.any? { |item| (item["kind"] || item[:kind]).to_s == "transfer" && (item["verified"] || item[:verified]) }) ? "passed" : "not_attempted",
          evidence_strength: verified.positive? ? "moderate" : "weak",
          planner_summary: "#{verified}/#{evidence.length} 条学习证据已通过验证。",
          metadata: { "provider" => "deterministic", "status" => "fallback" }
        )
      end

      private

      def normalize(value)
        value.to_s.downcase.gsub(/\s+/, "")
      end
    end
  end
end
