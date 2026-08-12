# frozen_string_literal: true

module Memury
  class EvidenceSignalProjector
    SIGNAL_KINDS = %w[item_error quiz_item rubric teacher_feedback].freeze

    def self.call(user:, state:)
      new(user:, state:).call
    end

    def initialize(user:, state:)
      @user = user
      @state = state.deep_stringify_keys
    end

    def call
      signals = Memury::AcademicEvidence.where(user:, verified: true, kind: SIGNAL_KINDS).to_a
      return state if signals.empty?

      projected = state.deep_dup
      concept = projected["concept"] ||= {}
      ratios = signals.filter_map do |item|
        score = item.metadata["score"]
        possible = item.metadata["points_possible"]
        next unless score && possible.to_f.positive?

        score.to_f / possible.to_f
      end
      pattern_count = signals.filter_map(&:error_pattern).uniq.length
      evidence_mastery = if ratios.any?
                           ratios.sum / ratios.length
                         else
                           0.68 - ([pattern_count, 3].min * 0.08)
                         end
      current = concept.fetch("mastery", 0.5).to_f
      concept["mastery"] = [current, evidence_mastery].min.clamp(0.0, 1.0).round(2)
      concept["confidence"] = [0.58 + (signals.length * 0.09), 0.94].min.round(2)
      concept["evidence_basis"] = "verified_assignment_evidence"
      concept["evidence_count"] = signals.length
      projected
    end

    private

    attr_reader :user, :state
  end
end
