# frozen_string_literal: true

require "spec_helper"

describe Memury::EvidenceSignalProjector do
  let(:user) { user_factory }
  let(:state) { { "concept" => { "mastery" => 0.78, "confidence" => 0.6 } } }

  it "projects verified assignment evidence into mastery and confidence" do
    Memury::AcademicEvidence.create!(
      user:, kind: "item_error", source_kind: "canvas", source_ref: "quiz-item-1",
      title: "Quiz item", summary: "Observed error", error_pattern: "sign convention",
      verified: true, confidence: 1.0, observed_at: Time.zone.now
    )

    result = described_class.call(user:, state:)

    expect(result.dig("concept", "mastery")).to be < 0.78
    expect(result.dig("concept", "evidence_basis")).to eq("verified_assignment_evidence")
  end

  it "does not change mastery or confidence from unverified evidence" do
    Memury::AcademicEvidence.create!(
      user:, kind: "item_error", source_kind: "demo", source_ref: "inferred-1",
      title: "Inference", summary: "Unverified", verified: false,
      confidence: 0.5, observed_at: Time.zone.now
    )

    expect(described_class.call(user:, state:)).to eq(state)
  end
end
