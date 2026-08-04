# frozen_string_literal: true

require "spec_helper"

describe Memury::PriorityScorer do
  it "is deterministic and protects against zero time cost" do
    args = { exam_relevance: 0.9, weakness: 0.8, forgetting_risk: 0.7, expected_gain: 0.6, time_cost: 0 }
    expect(described_class.call(**args)).to eq(described_class.call(**args))
    expect(described_class.call(**args)).to eq(3.024)
  end

  it "clamps normalized inputs" do
    expect(described_class.call(exam_relevance: 2, weakness: 1, forgetting_risk: 1, expected_gain: 1, time_cost: 10)).to eq(10.0)
  end
end
