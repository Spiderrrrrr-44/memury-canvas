# frozen_string_literal: true

module Memury
  class PriorityScorer
    MINIMUM_TIME_COST = 10.0

    def self.call(exam_relevance:, weakness:, forgetting_risk:, expected_gain:, time_cost:)
      factors = [exam_relevance, weakness, forgetting_risk, expected_gain].map { |value| value.to_f.clamp(0.0, 1.0) }
      (factors.reduce(:*) / [time_cost.to_f, MINIMUM_TIME_COST].max * 100).round(4)
    end
  end
end
