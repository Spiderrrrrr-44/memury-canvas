# frozen_string_literal: true

require "spec_helper"

describe Memury::SemesterCommandService do
  let(:now) { Time.zone.parse("2026-08-12 10:00:00") }
  let(:user) { user_factory }
  subject(:service) { described_class.new(user:, now:) }

  it "persists personal events and focus lifecycle state" do
    event = service.create_event(title: "健身", starts_at: now + 9.hours, ends_at: now + 11.hours,
                                 availability: "busy", recurrence_rule: "FREQ=WEEKLY")
    expect(event.reload).to have_attributes(title: "健身", recurrence_rule: "FREQ=WEEKLY")
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

  it "creates, associates, and resolves a semester question" do
    question = service.create_question(content: "如何判断是否漏力？", source_kind: "manual")
    service.update_question(question.id, status: "resolved", resolution_note: "已复核课程材料")
    expect(question.reload).to have_attributes(status: "resolved", resolution_note: "已复核课程材料")
    expect(question.resolved_at).to eq(now)
  end
end
