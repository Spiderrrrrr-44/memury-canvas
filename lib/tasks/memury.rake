# frozen_string_literal: true

namespace :memury do
  desc "Create or refresh the local Canvas demo student, course data, and deterministic Memury state"
  task demo_seed: :environment do
    login = ENV.fetch("LOGIN", "memury.student@example.test")
    account = Account.default
    account.enable_feature!(:memury)

    pseudonym = Pseudonym.active.find_by(account:, unique_id: login)
    unless pseudonym
      user = User.create!(
        name: "Memury Demo Student",
        short_name: "Memury Student",
        sortable_name: "Student, Memury Demo"
      )
      user.register!
      pseudonym = user.pseudonyms.create!(account:, unique_id: login)
      user.communication_channels.create!(path: login) { |channel| channel.workflow_state = "active" }
    end
    user = pseudonym.user

    course = account.courses.find_or_initialize_by(sis_source_id: "MEMURY-DEMO-MECH-101")
    course.name = "工程力学基础（Memury Demo）"
    course.course_code = "MECH-MEMURY-101"
    course.enrollment_term ||= account.default_enrollment_term
    course.save!
    course.offer! unless course.available?

    enrollment = course.student_enrollments.find_by(user:)
    enrollment ||= course.enroll_student(user, enrollment_state: "active")
    enrollment.update!(workflow_state: "active") unless enrollment.active?

    assignment_specs = [
      { title: "受力分析作业 2", due_at: 36.hours.from_now, points_possible: 20, submitted: false },
      { title: "第 2 章随堂测验", due_at: 2.days.from_now, points_possible: 10, submitted: true },
      { title: "工程力学期中复习", due_at: 4.days.from_now, points_possible: 30, submitted: false }
    ]

    assignments = assignment_specs.map do |spec|
      assignment = course.assignments.find_or_initialize_by(title: spec.fetch(:title))
      assignment.assign_attributes(
        due_at: spec.fetch(:due_at),
        points_possible: spec.fetch(:points_possible),
        submission_types: "online_text_entry"
      )
      assignment.save!
      assignment.publish! unless assignment.published?

      submission = assignment.find_or_create_submission(user)
      if spec.fetch(:submitted) && !submission.submitted?
        submission = assignment.submit_homework(
          user,
          submission_type: "online_text_entry",
          body: "Memury Demo：已完成第 2 章基础检查。"
        )
      end
      { assignment:, submission: }
    end

    profile = Memury::LearnerProfile.find_or_initialize_by(user:)
    profile.state = Memury::DemoState.build
    profile.last_synced_at = Time.zone.now
    profile.save!

    submitted_count = assignments.count { |item| item.fetch(:submission).submitted? }
    puts "Memury demo prepared for #{login}."
    puts "Canvas course #{course.id}: #{course.name}"
    puts "Published assignments: #{assignments.length}; submitted: #{submitted_count}; unsubmitted: #{assignments.length - submitted_count}."
    puts "If this login is new, set its password in Canvas before the first direct sign-in."
  end
end
