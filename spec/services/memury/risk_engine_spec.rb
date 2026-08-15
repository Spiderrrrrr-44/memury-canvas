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


  it "only applies SIS exam proximity to the matching course" do
    physics_exam = exam.merge("course_id" => "physics")
    mechanics = assignment.except("exam_relevance").merge("course_id" => "mechanics")
    physics = assignment.except("exam_relevance").merge("id" => "physics-task", "course_id" => "physics")

    result = described_class.call(assignments: [mechanics, physics], sis_events: [physics_exam], concept:,
                                  recent_activity_at: now, completed_assignment_ids: [], now:)

    expect(result.find { |item| item["id"] == "physics-task" }["risk_reasons"]).to include("三天内有相关考试")
    expect(result.find { |item| item["id"] == "mechanics-1" }["risk_reasons"]).not_to include("三天内有相关考试")
  end

  it "labels overdue and missing deadlines without presenting them as due in zero hours" do
    overdue = assignment.merge("due_at" => (now - 2.hours).iso8601)
    missing = assignment.merge("id" => "without-due-date", "due_at" => nil)

    result = described_class.call(assignments: [overdue, missing], sis_events: [], concept:,
                                  recent_activity_at: now, completed_assignment_ids: [], now:)

    expect(result.find { |item| item["id"] == "mechanics-1" }["risk_reasons"]).to include("作业已逾期，当前仍未提交")
    expect(result.find { |item| item["id"] == "without-due-date" }["risk_reasons"]).to include("Canvas 暂未提供截止时间")
    expect(result.flat_map { |item| item["risk_reasons"] }).not_to include("作业将在 0 小时内截止")
  end
end
