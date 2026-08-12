# frozen_string_literal: true

require "spec_helper"

describe Memury::DemoCourseCatalog do
  let(:now) { Time.zone.parse("2026-10-13 15:20:00") }

  it "provides a coherent six-course semester with nineteen tasks" do
    assignments = described_class.assignments(now:)

    expect(described_class.courses.pluck("id")).to contain_exactly("ME250", "TAM212", "MATH257", "CS101", "PHYS212", "RHET105")
    expect(assignments.length).to eq(19)
    expect(assignments.map { |item| item[:course_id] }.uniq.length).to eq(6)
    expect(assignments.find { |item| item[:id] == "ME250-HW4" }).to include(
      submitted: false, estimated_minutes: 200, weight_percent: 5
    )
  end

  it "keeps verified and pending evidence distinct" do
    evidence = described_class.evidence

    expect(evidence.count { |item| item[:verified] }).to eq(9)
    expect(evidence.find { |item| item[:id] == "EV-010" }).to include(verified: false)
  end
end
