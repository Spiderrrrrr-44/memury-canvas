# frozen_string_literal: true

require "spec_helper"

describe Memury::RiskEngine do
  let(:now) { Time.zone.parse("2026-08-06 10:00:00") }
  let(:assignment) do
    {
      "id" => "mechanics-1",
      "course_name" => "工程力学基础",
      "title" => "受力分析作业",
      "due_at" => (now + 24.hours).iso8601,
      "submitted" => false,
      "exam_relevance" => 1.0
    }
  end
  let(:exam) { { "exam" => true, "starts_at" => (now + 3.days).iso8601 } }
  let(:concept) { { "mastery" => 0.4 } }

  it "orders urgent, unsubmitted, exam-relevant work first with reasons" do
    lower_risk = assignment.merge("id" => "later", "due_at" => (now + 6.days).iso8601, "submitted" => true, "exam_relevance" => 0.1)
    result = described_class.call(assignments: [lower_risk, assignment], sis_events: [exam], concept:,
                                  recent_activity_at: now - 3.days, completed_assignment_ids: [], now:)

    expect(result.first["id"]).to eq("mechanics-1")
    expect(result.first["risk_reasons"]).to include("Canvas 显示尚未提交", "三天内有相关考试", "对应知识点掌握度偏低")
  end

  it "lowers risk deterministically after the target intervention is completed" do
    before = described_class.call(assignments: [assignment], sis_events: [exam], concept:,
                                  recent_activity_at: now - 3.days, completed_assignment_ids: [], now:).first
    after = described_class.call(assignments: [assignment], sis_events: [exam], concept:,
                                 recent_activity_at: now, completed_assignment_ids: ["mechanics-1"], now:).first

    expect(after["risk"]).to be < before["risk"]
    expect(after["risk_reasons"]).to eq(["已完成本轮补强，风险已显著下降"])
  end
end
