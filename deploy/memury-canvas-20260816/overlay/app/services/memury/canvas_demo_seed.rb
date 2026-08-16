# frozen_string_literal: true

module Memury
  class CanvasDemoSeed
    LEGACY_ME250_SIS_ID = "MEMURY-DEMO-MECH-101"

    def self.call(account:, user:, now: Time.zone.now)
      new(account:, user:, now:).call
    end

    def initialize(account:, user:, now:)
      @account = account
      @user = user
      @now = now
    end

    def call
      courses = seed_courses
      assignments = seed_assignments(courses)
      course_events = seed_course_events(courses)
      personal_events = seed_personal_events
      { courses:, assignments:, course_events:, personal_events: }
    end

    private

    attr_reader :account, :user, :now

    def seed_courses
      legacy_me250 = account.courses.find_by(sis_source_id: LEGACY_ME250_SIS_ID)
      Memury::DemoCourseCatalog.courses.to_h do |attributes|
        course = if attributes.fetch("id") == "ME250" && legacy_me250
                   legacy_me250
                 else
                   account.courses.find_or_initialize_by(sis_source_id: sis_id(attributes.fetch("id")))
                 end
        course.assign_attributes(
          sis_source_id: sis_id(attributes.fetch("id")),
          name: attributes.fetch("name"),
          course_code: attributes.fetch("id"),
          enrollment_term: course.enrollment_term || account.default_enrollment_term,
          public_description: course_description(attributes)
        )
        course.save!
        course.offer! unless course.available?
        enrollment = course.student_enrollments.find_by(user:)
        enrollment ||= course.enroll_student(user, enrollment_state: "active")
        enrollment.update!(workflow_state: "active") unless enrollment.active?
        [attributes.fetch("id"), course]
      end
    end

    def seed_assignments(courses)
      Memury::DemoCourseCatalog.assignments(now:).map do |attributes|
        course = courses.fetch(attributes.fetch(:course_id))
        assignment = course.assignments.find_or_initialize_by(title: attributes.fetch(:title))
        assignment.assign_attributes(
          due_at: attributes.fetch(:due_at), points_possible: attributes.fetch(:points_possible),
          description: "[MEMURY DEMO] #{attributes.fetch(:task_type)} · #{attributes.fetch(:progress_label)} · 权重 #{attributes.fetch(:weight_percent)}%",
          submission_types: "online_text_entry"
        )
        assignment.save!
        assignment.publish! unless assignment.published?
        if attributes.fetch(:submitted) && !assignment.find_or_create_submission(user).submitted?
          assignment.submit_homework(user, submission_type: "online_text_entry", body: "Memury Demo submission — no official grade written.")
        end
        { assignment:, submission: assignment.find_or_create_submission(user), catalog: attributes }
      end
    end

    def seed_course_events(courses)
      Memury::DemoCourseCatalog.calendar_events(now:).filter_map do |attributes|
        next unless attributes[:course_id]

        course = courses.fetch(attributes.fetch(:course_id))
        event = course.calendar_events.find_or_initialize_by(title: "[Memury Demo] #{attributes.fetch(:title)}")
        event.assign_attributes(
          start_at: attributes.fetch(:starts_at), end_at: attributes.fetch(:ends_at),
          location_name: Memury::DemoCourseCatalog.courses.find { |item| item.fetch("id") == attributes.fetch(:course_id) }.fetch("room"),
          description: "[MEMURY DEMO COURSE EVENT] #{attributes.fetch(:recurrence_rule)}"
        )
        event.save!
        event
      end
    end

    def seed_personal_events
      Memury::DemoCourseCatalog.calendar_events(now:).filter_map do |attributes|
        next if attributes[:course_id]

        event = user.calendar_events.find_or_initialize_by(title: "[Memury Demo] #{attributes.fetch(:title)}")
        event.assign_attributes(
          start_at: attributes.fetch(:starts_at), end_at: attributes.fetch(:ends_at),
          description: "[MEMURY DEMO PERSONAL EVENT] #{attributes.fetch(:availability)}"
        )
        event.save!
        event
      end
    end

    def sis_id(course_id)
      "MEMURY-DEMO-#{course_id}"
    end

    def course_description(attributes)
      [
        "[MEMURY DEMO COURSE — FICTIONAL DATA]",
        "教师：#{attributes.fetch('instructor')}",
        "学分：#{attributes.fetch('credits')}",
        "课表：#{attributes.fetch('schedule')}",
        "教室：#{attributes.fetch('room')}",
        "进度：#{attributes.fetch('progress')}"
      ].join("\n")
    end
  end
end
