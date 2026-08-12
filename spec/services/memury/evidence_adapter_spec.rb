# frozen_string_literal: true

require "spec_helper"

describe Memury::EvidenceAdapter do
  it "labels persisted Canvas evidence and never treats inferred profile notes as verified" do
    user = user_factory
    Memury::AcademicEvidence.create!(
      user:, kind: "teacher_feedback", source_kind: "canvas", source_ref: "feedback-1",
      title: "教师反馈", summary: "需要先确认研究对象", verified: true,
      confidence: 1.0, observed_at: Time.zone.now
    )
    result = described_class.call(user:, state: { "evidence" => [{ "title" => "AI 推断", "observed_at" => Time.zone.now.iso8601 }] })

    expect(result.first).to include("source_label" => "Canvas 正式证据", "verified" => true)
    expect(result.last).to include("official_or_inferred" => "Inferred", "verified" => false)
  end

  it "maps Demo evidence to the stable assignment id used by shareable product routes" do
    user = user_factory
    course = course_factory
    assignment = assignment_model(course:, title: "受力分析作业 2")
    Memury::AcademicEvidence.create!(
      user:, course:, assignment:, kind: "item_error", source_kind: "demo",
      source_ref: "assignment-#{assignment.id}-pattern", title: "失分项",
      summary: "重复错误", verified: true, confidence: 0.9, observed_at: Time.zone.now
    )

    result = described_class.call(
      user:,
      state: { "assignments" => [{ "id" => "mech-force", "title" => "受力分析作业 2" }] }
    )

    expect(result.first["assignment_id"]).to eq("mech-force")
  end
end
