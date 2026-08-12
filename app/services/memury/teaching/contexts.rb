# frozen_string_literal: true

module Memury
  module Teaching
    # Namespace marker keeps this multi-value-object file compatible with
    # Rails' Zeitwerk expectation for contexts.rb while the public context
    # classes remain directly under Memury::Teaching.
    module Contexts; end

    class PlannerContext
      ATTRIBUTES = %i[tasks deadlines exams submission_states time_budget knowledge_gaps verified_results risk_state plan_state].freeze
      attr_reader(*ATTRIBUTES)

      def initialize(**attributes)
        ATTRIBUTES.each { |attribute| instance_variable_set("@#{attribute}", attributes.fetch(attribute)) }
        freeze
      end

      def self.from_state(state)
        state = state.deep_stringify_keys
        new(
          tasks: state.fetch("assignments", []).map { |item| item.slice("id", "course_id", "course_name", "title", "due_at", "submitted", "estimated_minutes") },
          deadlines: state.fetch("sis_events", []).map { |item| item.slice("id", "title", "starts_at", "exam") },
          exams: state.fetch("sis_events", []).select { |item| item["exam"] }.map { |item| item.slice("id", "title", "starts_at") },
          submission_states: state.fetch("assignments", []).to_h { |item| [item["id"].to_s, item.slice("submitted", "score")] },
          time_budget: state.dig("today", "total_minutes") || state.fetch("assignments", []).sum { |item| item.fetch("estimated_minutes", 0).to_i },
          knowledge_gaps: [state.fetch("concept", {}).slice("name", "mastery", "confidence", "misconception")],
          verified_results: state.fetch("evidence", []).select { |item| item["verified"] },
          risk_state: state.fetch("risks", []),
          plan_state: state.fetch("study_blocks", []).map { |item| item.slice("id", "stage", "starts_at", "duration_minutes", "status") }
        )
      end

      def to_h
        ATTRIBUTES.to_h { |attribute| [attribute.to_s, public_send(attribute)] }
      end
    end

    class TutorContext
      ATTRIBUTES = %i[course_or_subject knowledge_point question scoring_basis student_answer learner_state_summary recent_misconceptions course_materials diagnosis].freeze
      attr_reader(*ATTRIBUTES)

      def initialize(**attributes)
        ATTRIBUTES.each { |attribute| instance_variable_set("@#{attribute}", attributes.fetch(attribute, nil)) }
        freeze
      end

      def self.from_state(state, student_answer: "")
        state = state.deep_stringify_keys
        concept = state.fetch("concept", {})
        assignment = state.fetch("assignments", []).find { |item| item["id"].to_s == state.dig("learning_session", "target_assignment_id").to_s }
        new(
          course_or_subject: assignment&.fetch("course_name", nil) || state.dig("canvas", "courses", 0, "name") || "当前课程",
          knowledge_point: concept["name"].to_s,
          question: state.dig("learning_session", "recall_question").to_s,
          scoring_basis: concept["reference_answer"].to_s,
          student_answer: student_answer.to_s,
          learner_state_summary: {
            "knowledge_point" => concept["name"],
            "mastery" => concept["mastery"],
            "confidence" => concept["confidence"],
            "recent_misconception" => concept["misconception"],
            "evidence_count" => state.fetch("evidence", []).length
          }.compact,
          recent_misconceptions: state.fetch("hypotheses", []).first(3),
          course_materials: state.fetch("course_materials", []).first(5),
          diagnosis: state["diagnostic"]
        )
      end

      def to_h
        ATTRIBUTES.to_h { |attribute| [attribute.to_s, public_send(attribute)] }.compact
      end
    end

    class PracticeContext
      ATTRIBUTES = %i[course_or_subject knowledge_point transfer_question scoring_basis difficulty source_materials recent_misconceptions].freeze
      attr_reader(*ATTRIBUTES)

      def initialize(**attributes)
        ATTRIBUTES.each { |attribute| instance_variable_set("@#{attribute}", attributes.fetch(attribute)) }
        freeze
      end

      def self.from_state(state)
        tutor = TutorContext.from_state(state)
        diagnostic = state.fetch("diagnostic", {})
        new(
          course_or_subject: tutor.course_or_subject,
          knowledge_point: tutor.knowledge_point,
          transfer_question: diagnostic["transfer_question"].to_s,
          scoring_basis: tutor.scoring_basis,
          difficulty: "transfer",
          source_materials: tutor.course_materials,
          recent_misconceptions: tutor.recent_misconceptions
        )
      end

      def to_h
        ATTRIBUTES.to_h { |attribute| [attribute.to_s, public_send(attribute)] }.compact
      end
    end

    class ValidatorContext
      attr_reader :course_or_subject,
                  :knowledge_point,
                  :question,
                  :candidate_prompt,
                  :candidate_expected_answer,
                  :candidate_explanation,
                  :difficulty,
                  :source_materials,
                  :student_answer,
                  :reference_answer,
                  :legacy_correct,
                  :hint_dependent

      def initialize(course_or_subject:,
                     knowledge_point:,
                     question:,
                     candidate_prompt:,
                     candidate_expected_answer:,
                     candidate_explanation:,
                     difficulty:,
                     source_materials:,
                     student_answer: "",
                     reference_answer: "",
                     legacy_correct: nil,
                     hint_dependent: false)
        @course_or_subject = course_or_subject
        @knowledge_point = knowledge_point
        @question = question
        @candidate_prompt = candidate_prompt
        @candidate_expected_answer = candidate_expected_answer
        @candidate_explanation = candidate_explanation
        @difficulty = difficulty
        @source_materials = source_materials
        @student_answer = student_answer
        @reference_answer = reference_answer
        @legacy_correct = legacy_correct
        @hint_dependent = !!hint_dependent
        freeze
      end

      def self.for_candidate(candidate:, context:)
        new(
          course_or_subject: context.course_or_subject,
          knowledge_point: context.knowledge_point,
          question: context.transfer_question,
          candidate_prompt: candidate.prompt,
          candidate_expected_answer: candidate.expected_answer,
          candidate_explanation: candidate.explanation,
          difficulty: candidate.difficulty,
          source_materials: context.source_materials,
          reference_answer: context.scoring_basis
        )
      end

      def self.for_transfer(candidate:, context:, student_answer:, legacy_correct: nil, hint_dependent: false)
        for_candidate(candidate:, context:).with_transfer(
          student_answer:, reference_answer: context.scoring_basis, legacy_correct:, hint_dependent:
        )
      end

      def with_transfer(student_answer:, reference_answer:, legacy_correct: nil, hint_dependent: false)
        self.class.new(
          course_or_subject:,
          knowledge_point:,
          question:,
          candidate_prompt:,
          candidate_expected_answer:,
          candidate_explanation:,
          difficulty:,
          source_materials:,
          student_answer:,
          reference_answer:,
          legacy_correct:,
          hint_dependent:
        )
      end

      def candidate_h
        {
          "prompt" => candidate_prompt,
          "expected_answer" => candidate_expected_answer,
          "explanation" => candidate_explanation,
          "difficulty" => difficulty
        }
      end

      def to_h
        {
          "course_or_subject" => course_or_subject,
          "knowledge_point" => knowledge_point,
          "question" => question,
          "candidate_prompt" => candidate_prompt,
          "candidate_expected_answer" => candidate_expected_answer,
          "candidate_explanation" => candidate_explanation,
          "difficulty" => difficulty,
          "source_materials" => source_materials,
          "student_answer" => student_answer,
          "reference_answer" => reference_answer,
          "legacy_correct" => legacy_correct,
          "hint_dependent" => hint_dependent
        }.compact
      end
    end

    class EvidenceContext
      attr_reader :evidence

      def initialize(evidence:)
        @evidence = Array(evidence).freeze
        freeze
      end

      def to_h
        { "evidence" => evidence }
      end
    end
  end
end
