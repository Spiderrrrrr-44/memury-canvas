# frozen_string_literal: true

require "spec_helper"

describe Memury::Scheduler do
  let(:now) { Time.zone.parse("2026-08-12 09:00:00") }
  let(:user) { user_factory }
  let(:assignment) do
    {
      "id" => "demo-task", "course_name" => "工程力学", "title" => "长作业",
      "due_at" => (now + 3.days).iso8601, "submitted" => false,
      "estimated_minutes" => 140, "risk" => 0.9,
      "risk_reasons" => ["截止临近", "存在重复错误"]
    }
  end

  it "splits long work, avoids busy events, and preserves locked blocks when replanning" do
    Memury::CalendarEvent.create!(user:, title: "固定课程", starts_at: now.change(hour: 9),
                                  ends_at: now.change(hour: 12), source_kind: "course", availability: "busy")
    locked = Memury::PlanBlock.create!(user:, title: "用户锁定", starts_at: now.change(hour: 14),
                                       ends_at: now.change(hour: 15), reason: "用户锁定", locked: true)

    result = described_class.call(user:, assignments: [assignment], now:)

    expect(result.length).to eq(2)
    expect(result.sum { |block| (block.ends_at - block.starts_at) / 60 }).to eq(140)
    expect(result).to all(satisfy { |block| block.starts_at >= now.change(hour: 12) })
    expect(Memury::PlanBlock.exists?(locked.id)).to be true
  end

  it "uses the remaining time before an urgent deadline instead of silently returning no blocks" do
    urgent = assignment.merge("estimated_minutes" => 30, "due_at" => (now + 2.hours).iso8601)

    result = described_class.call(user:, assignments: [urgent], now:)

    expect(result.length).to eq(1)
    expect(result.first.ends_at).to be <= now + 2.hours
    expect(result.unscheduled).to be_empty
  end

  it "reports an explicit reason when no legal slot exists" do
    impossible = assignment.merge("estimated_minutes" => 30, "due_at" => (now + 10.minutes).iso8601)

    result = described_class.call(user:, assignments: [impossible], now:)

    expect(result.blocks).to be_empty
    expect(result.unscheduled.first).to include("assignment_id" => "demo-task")
  end

  it "replaces unlocked planned blocks instead of creating duplicates" do
    2.times { described_class.call(user:, assignments: [assignment], now:) }

    expect(Memury::PlanBlock.where(user:, status: "planned").count).to eq(2)
  end
end
