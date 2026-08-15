# frozen_string_literal: true

require "spec_helper"

describe Memury::SemesterCommandService do
  let(:now) { Time.zone.parse("2026-08-12 10:00:00") }
  let(:user) { user_factory }
  subject(:service) { described_class.new(user:, now:) }

  it "persists personal events and focus lifecycle state" do
    event = service.create_event(title: "健身", starts_at: now + 9.hours, ends_at: now + 11.hours,
                                 availability: "busy", recurrence_rule: "FREQ=WEEKLY")
    expect(event.reload).to have_attributes(title: "健身", recurrence_rule: nil)
    service.update_event(event.id, title: "晚间健身", starts_at: now + 10.hours, ends_at: now + 12.hours)
    expect(event.reload).to have_attributes(title: "晚间健身", starts_at: now + 10.hours)

    session = service.focus("start", {})
    expect(session).to be_status_active
    expect(service.focus("pause", {}).reload).to be_status_paused
    expect(service.focus("resume", {}).reload).to be_status_active
    expect(service.focus("finish", {}).reload).to be_status_completed

    service.delete_event(event.id)
    expect(Memury::CalendarEvent.exists?(event.id)).to be false
  end

  it "rejects invalid and obvious duplicate personal busy events" do
    attributes = { title: "实验室", starts_at: now + 3.hours, ends_at: now + 4.hours, availability: "busy" }
    service.create_event(attributes)

    expect { service.create_event(attributes) }.to raise_error(ActiveRecord::RecordInvalid, /duplicate calendar event/)
    expect do
      service.create_event(attributes.merge(title: "错误时间", ends_at: now + 2.hours))
    end.to raise_error(ActiveRecord::RecordInvalid, /must be after starts_at/)
  end

  it "rejects moving a study block into busy time or after its assignment deadline" do
    due_at = now + 8.hours
    block = Memury::PlanBlock.create!(
      user:, title: "复习", starts_at: now + 1.hour, ends_at: now + 2.hours,
      reason: "风险优先", metadata: { "due_at" => due_at.iso8601 }
    )
    Memury::CalendarEvent.create!(
      user:, title: "课程", starts_at: now + 3.hours, ends_at: now + 4.hours,
      source_kind: "course", availability: "busy"
    )

    expect do
      service.update_plan_block(block.id, starts_at: now + 3.hours, ends_at: now + 3.5.hours)
    end.to raise_error(ActiveRecord::RecordInvalid, /overlaps a busy event/)
    expect do
      service.update_plan_block(block.id, starts_at: now + 7.5.hours, ends_at: now + 9.hours)
    end.to raise_error(ActiveRecord::RecordInvalid, /assignment deadline/)
  end

  it "creates, associates, and resolves a semester question" do
    question = service.create_question(content: "如何判断是否漏力？", source_kind: "manual")
    service.update_question(question.id, status: "resolved", resolution_note: "已复核课程材料")
    expect(question.reload).to have_attributes(status: "resolved", resolution_note: "已复核课程材料")
    expect(question.resolved_at).to eq(now)
  end
end
