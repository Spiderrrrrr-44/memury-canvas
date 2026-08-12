# frozen_string_literal: true

require "spec_helper"

describe Memury::LearnerStateUpdater do
  it "weights an unhinted correct transfer more strongly" do
    common = { current_mastery: 0.4, diagnostic_correct: false, hypothesis_verified: true, transfer_correct: true }
    hinted = described_class.call(**common, used_hint: true)
    unhinted = described_class.call(**common, used_hint: false)
    expect(hinted[:delta]).to eq(0.11)
    expect(hinted[:delta]).to be <= 0.12
    expect(unhinted[:delta]).to eq(0.23)
    expect(unhinted[:mastery]).to be > hinted[:mastery]
    expect(unhinted[:reason]).to include("无关键提示")
  end

  it "only changes state from supplied evidence and remains deterministic" do
    args = { current_mastery: 0.4, diagnostic_correct: false, used_hint: false, hypothesis_verified: false, transfer_correct: false }
    first_result = described_class.call(**args)
    expect(described_class.call(**args)).to eq(first_result)
  end

  it "preserves learner state when validation has not passed" do
    result = described_class.call(
      current_mastery: 0.4,
      current_confidence: 0.73,
      diagnostic_correct: true,
      used_hint: false,
      hypothesis_verified: true,
      transfer_correct: false,
      validated: false
    )

    expect(result).to include(mastery: 0.4, previous_mastery: 0.4, delta: 0.0, confidence: 0.73)
  end
end
