# frozen_string_literal: true

module Memury
  class EvidenceAdapter
    def self.call(user:, state:)
      new(user:, state:).call
    end

    def initialize(user:, state:)
      @user = user
      @state = state.deep_stringify_keys
    end

    def call
      persisted = Memury::AcademicEvidence.where(user: @user).order(observed_at: :desc).map { |item| serialize(item) }
      inferred = @state.fetch("evidence", []).map.with_index do |item, index|
        {
          "id" => "learner-state-#{index}",
          "kind" => "learning_trace",
          "title" => item["title"],
          "summary" => item["title"],
          "source_kind" => "memury_inference",
          "source_label" => "Memury 推断",
          "official_or_inferred" => "Inferred",
          "verified" => false,
          "confidence" => 0.5,
          "observed_at" => item["observed_at"]
        }
      end
      persisted + inferred
    end

    private

    def serialize(item)
      assignment_ref = public_assignment_ref(item)
      {
        "id" => item.id.to_s,
        "kind" => item.kind,
        "title" => item.title,
        "summary" => item.summary,
        "concept" => item.concept,
        "error_pattern" => item.error_pattern,
        "source_kind" => item.source_kind,
        "source_label" => source_label(item.source_kind),
        "official_or_inferred" => item.source_kind == "canvas" ? "Official" : "Simulated",
        "verified" => item.verified,
        "confidence" => item.confidence&.to_f,
        "observed_at" => item.observed_at.iso8601,
        "course_id" => item.course_id&.to_s,
        "assignment_id" => assignment_ref,
        "metadata" => item.metadata.slice("score", "points_possible", "attempt", "late", "missing", "feedback")
      }.compact
    end

    def public_assignment_ref(item)
      return item.assignment_id&.to_s unless item.source_kind == "demo"

      catalog_ref = item.metadata["demo_assignment_id"]
      return catalog_ref if catalog_ref.present?

      @state.fetch("assignments", []).find do |assignment|
        item.source_ref.include?(assignment.fetch("id", "").to_s) ||
          item.assignment&.title == assignment["title"]
      end&.fetch("id", nil) || item.assignment_id&.to_s
    end

    def source_label(source_kind)
      source_kind == "canvas" ? "Canvas 正式证据" : "Demo Evidence"
    end
  end
end
