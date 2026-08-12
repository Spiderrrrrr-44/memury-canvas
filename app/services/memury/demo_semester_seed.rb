# frozen_string_literal: true

module Memury
  class DemoSemesterSeed
    def self.call(user:, course:, assignments:, now: Time.zone.now)
      new(user:, course:, assignments:, now:).call
    end

    def initialize(user:, course:, assignments:, now:)
      @user = user
      @fallback_course = course
      @canvas_assignments = assignments.map { |item| item.fetch(:assignment) }
      @now = now
    end

    def call
      seed_evidence
      seed_calendar
      seed_focus
      seed_questions
    end

    private

    attr_reader :user, :fallback_course, :canvas_assignments, :now

    def seed_evidence
      Memury::DemoCourseCatalog.evidence.each do |attributes|
        record = Memury::AcademicEvidence.find_or_initialize_by(
          user:, source_kind: attributes.fetch(:source_kind), source_ref: attributes.fetch(:source_ref)
        )
        record.assign_attributes(
          kind: attributes.fetch(:kind), title: attributes.fetch(:title), summary: attributes.fetch(:summary),
          concept: attributes.fetch(:concept), error_pattern: attributes.fetch(:error_pattern),
          verified: attributes.fetch(:verified), confidence: attributes.fetch(:confidence),
          observed_at: now - 1.day, metadata: { "demo_assignment_id" => attributes.fetch(:assignment_id) }
        )
        record.save!
      end
    end

    def seed_calendar
      Memury::DemoCourseCatalog.calendar_events(now:).each do |attributes|
        event = Memury::CalendarEvent.find_or_initialize_by(user:, title: attributes.fetch(:title), source_kind: attributes.fetch(:source_kind))
        event.assign_attributes(attributes.slice(:starts_at, :ends_at, :availability, :recurrence_rule, :locked).merge(
          metadata: { "demo_event_id" => attributes.fetch(:id), "course_ref" => attributes[:course_id] }.compact
        ))
        event.save!
      end
    end

    def seed_focus
      Memury::DemoCourseCatalog.focus_records(now:).each do |attributes|
        started_at = attributes.fetch(:started_at).change(min: 0, sec: 0)
        session = Memury::FocusSession.find_or_initialize_by(user:, started_at:)
        minutes = attributes.fetch(:minutes)
        session.assign_attributes(status: "completed", ended_at: started_at + minutes.minutes,
                                  active_seconds: minutes.minutes.to_i)
        session.save!
      end
    end

    def seed_questions
      Memury::DemoCourseCatalog.questions(now:).each do |attributes|
        item = Memury::LearningQuestion.find_or_initialize_by(user:, content: attributes.fetch(:content))
        item.assign_attributes(
          concept: attributes.fetch(:assignment_id), source_kind: "demo_evidence",
          status: attributes.fetch(:status), review_at: attributes.fetch(:review_at),
          resolution_note: attributes.fetch(:status) == "resolved" ? "已通过课程材料和作业反馈复核。" : nil,
          resolved_at: attributes.fetch(:status) == "resolved" ? now - 1.day : nil
        )
        item.save!
      end
    end
  end
end
