# frozen_string_literal: true

require "spec_helper"

describe Memury::LearnerStateUpdater do
  it "weights an unhinted correct transfer more strongly" do
    common = { current_mastery: 0.4, diagnostic_correct: false, hypothesis_verified: true, transfer_correct: true }
    hinted = described_class.call(**common, used_hint: true)
    unhinted = described_class.call(**common, used_hint: false)
    expect(unhinted[:mastery]).to be > hinted[:mastery]
    expect(unhinted[:reason]).to include("无关键提示")
  end

  it "only changes state from supplied evidence and remains deterministic" do
    args = { current_mastery: 0.4, diagnostic_correct: false, used_hint: false, hypothesis_verified: false, transfer_correct: false }
    expect(described_class.call(**args)).to eq(described_class.call(**args))
  end
end
