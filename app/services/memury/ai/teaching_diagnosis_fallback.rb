# frozen_string_literal: true

module Memury
  module Ai
    module TeachingDiagnosisFallback
      module_function

      def build(context)
        answer = context[:student_answer].to_s.strip
        reference_answer = context[:scoring_basis].to_s.strip
        course_or_subject = context[:course_or_subject].presence || "课程"
        knowledge_point = context[:knowledge_point].presence || "当前知识点"
        question = context[:question].presence || "请解释你的思路。"

        judgment, misconception_type, confidence = classify(answer, reference_answer)
        evidence = build_evidence(answer, question, reference_answer)
        diagnosis_summary = build_summary(judgment, misconception_type, knowledge_point)

        {
          "diagnosis_summary" => diagnosis_summary,
          "answer_judgment" => judgment,
          "misconception_type" => misconception_type,
          "evidence" => evidence,
          "confidence" => confidence,
          "verification_question" => verification_question(course_or_subject, knowledge_point),
          "hint" => hint(course_or_subject, knowledge_point, reference_answer),
          "transfer_question" => transfer_question(course_or_subject, knowledge_point),
          "learner_state_suggestion" => {
            "skill" => knowledge_point,
            "suggested_status" => suggested_status(judgment, misconception_type),
            "reason" => suggested_reason(judgment, misconception_type, knowledge_point)
          }
        }
      end

      def classify(answer, reference_answer)
        return ["uncertain", "insufficient_evidence", 0.22] if answer.blank?
        return ["uncertain", "guessing", 0.28] if answer.length < 12 || answer.match?(/不知道|不会|随便|guess/i)

        if reference_answer.present? && contains_reference_answer?(answer, reference_answer)
          return ["correct", "insufficient_evidence", 0.88]
        end

        return ["incorrect", "calculation", 0.52] if answer.match?(/[0-9]+|[\+\-\*\/=]/)
        return ["incorrect", "procedural", 0.56] if answer.match?(/步骤|先|然后|接着|操作|procedure/i)
        return ["incorrect", "incomplete", 0.6] if answer.match?(/但|不过|只是|可能|大概/)

        ["incorrect", "conceptual", 0.66]
      end

      def contains_reference_answer?(answer, reference_answer)
        normalized_answer = normalize_text(answer)
        normalized_reference = normalize_text(reference_answer)
        return true if normalized_reference.present? && normalized_answer.include?(normalized_reference)

        reference_keywords = normalized_reference.split(/[[:space:][:punct:]]+/).reject(&:blank?).uniq
        return false if reference_keywords.empty?

        matches = reference_keywords.count { |keyword| normalized_answer.include?(keyword) }
        matches >= [reference_keywords.length / 2.0, 2].max
      end

      def build_evidence(answer, question, reference_answer)
        snippets = []
        snippets << snippet_from(answer, reference_answer)
        snippets << snippet_from(answer, question)
        snippets = snippets.compact.uniq.first(3)
        snippets.presence || ["学生回答证据不足，暂时无法提取有效片段"]
      end

      def snippet_from(answer, needle)
        return nil if answer.blank? || needle.blank?

        normalized_answer = normalize_text(answer)
        normalized_needle = normalize_text(needle)
        return normalized_answer.first(80) if normalized_needle.blank?
        return normalized_needle.first(80) if normalized_answer.include?(normalized_needle)

        words = normalized_needle.split(/[[:space:][:punct:]]+/).reject(&:blank?)
        return normalized_answer.first(80) if words.empty?

        matched = words.find { |word| normalized_answer.include?(word) }
        return nil unless matched

        index = normalized_answer.index(matched) || 0
        normalized_answer[[index - 12, 0].max, 80]
      end

      def build_summary(judgment, misconception_type, knowledge_point)
        case judgment
        when "correct"
          "回答已抓住#{knowledge_point}的关键方向，接下来用验证题确认是否能稳定迁移。"
        when "uncertain"
          "当前回答证据不足，暂时只能判断为#{misconception_type}。"
        else
          "当前回答显示#{knowledge_point}存在#{misconception_type}倾向。"
        end
      end

      def verification_question(course_or_subject, knowledge_point)
        "请再用一句话说明，在#{course_or_subject}中，#{knowledge_point}为什么不能被当作同一个物体上的平衡力？"
      end

      def hint(course_or_subject, knowledge_point, reference_answer)
        base_hint = "先分清“力的作用对象”，再判断是不是同一物体上的力。"
        return base_hint if reference_answer.blank?

        "#{base_hint} 这道题里，#{knowledge_point}要结合受力物体来判断。"
      end

      def transfer_question(course_or_subject, knowledge_point)
        "换个情境：在#{course_or_subject}里，#{knowledge_point}如果出现在斜面或电梯场景中，你会先检查哪两个受力对象？"
      end

      def suggested_status(judgment, misconception_type)
        return "strengthened" if judgment == "correct"
        return "review_needed" if %w[conceptual procedural calculation].include?(misconception_type)

        "needs_evidence"
      end

      def suggested_reason(judgment, misconception_type, knowledge_point)
        case judgment
        when "correct"
          "#{knowledge_point}已有较好证据，可用迁移题巩固。"
        when "uncertain"
          "当前证据不足，建议先补充最小验证题。"
        else
          "#{knowledge_point}的#{misconception_type}信号较强，先用验证题锁定错因。"
        end
      end

      def normalize_text(value)
        value.to_s.gsub(/\s+/, " ").strip
      end
      private_class_method :classify, :contains_reference_answer?, :build_evidence, :snippet_from,
                           :build_summary, :verification_question, :hint, :transfer_question,
                           :suggested_status, :suggested_reason, :normalize_text
    end
  end
end
