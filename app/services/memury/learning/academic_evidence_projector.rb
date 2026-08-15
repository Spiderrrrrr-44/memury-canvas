# frozen_string_literal: true

module Memury
  module Learning
    # Promotes only trusted, verified learning outcomes into semester memory.
    # Graph shape, provider confidence, and generated content are never enough.
    class AcademicEvidenceProjector
      TRUSTED_BASES = %w[
        trusted_course_source
        deterministic_rule
        independent_model_validation
      ].freeze

      class << self
        def call(user:, session:, evidence:)
          new(user:, session:, evidence:).call
        end
      end

      def initialize(user:, session:, evidence:)
        @user = user
        @session = session
        @evidence = evidence
      end

      def call
        return unless Memury::AcademicEvidence.table_exists?
        return unless evidence.kind == "transfer_validation" && evidence.verified?
        return unless TRUSTED_BASES.include?(payload["validation_basis"])

        record = Memury::AcademicEvidence.find_or_initialize_by(
          user:,
          source_kind: "memury_learning_session",
          source_ref: "learning-evidence-#{evidence.id}"
        )
        record.assign_attributes(
          course: session.course,
          assignment: session.assignment,
          kind: "quiz_item",
          title: "迁移验证通过",
          summary: safe_summary,
          concept: session.metadata.to_h["concept_id"].presence || session.objective,
          verified: true,
          confidence: evidence.confidence,
          observed_at: evidence.observed_at,
          metadata: {
            "score" => 1,
            "points_possible" => 1,
            "learning_session_id" => session.id,
            "learning_evidence_id" => evidence.id,
            "validation_basis" => payload["validation_basis"],
            "assignment_ref" => session.assignment_ref,
            "course_ref" => session.course_ref
          }.compact
        )
        record.save!
        record
      end

      private

      attr_reader :user, :session, :evidence

      def payload
        @payload ||= evidence.payload.to_h.deep_stringify_keys
      end

      def safe_summary
        payload["summary"].to_s.squish.truncate(240).presence || "可信迁移验证已完成"
      end
    end
  end
end
