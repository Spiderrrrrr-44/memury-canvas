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

    canvas_demo = Memury::CanvasDemoSeed.call(account:, user:)
    courses = canvas_demo.fetch(:courses)
    assignments = canvas_demo.fetch(:assignments)
    course = courses.fetch("ME250")

    profile = Memury::LearnerProfile.find_or_initialize_by(user:)
    profile.state = Memury::DemoState.build
    profile.last_synced_at = Time.zone.now
    profile.save!
    Memury::DemoSemesterSeed.call(user:, course:, assignments:)
    ranked = Memury::RiskEngine.call(assignments: profile.state.fetch("assignments"), sis_events: profile.state.fetch("sis_events"), concept: profile.state.fetch("concept"), recent_activity_at: profile.state["recent_activity_at"], completed_assignment_ids: [])
    Memury::Scheduler.call(user:, assignments: ranked)

    submitted_count = assignments.count { |item| item.fetch(:submission).submitted? }
    puts "Memury demo prepared for #{login}."
    puts "Canvas demo courses: #{courses.length}; native calendar events: #{canvas_demo.fetch(:course_events).length + canvas_demo.fetch(:personal_events).length}."
    puts "Published assignments: #{assignments.length}; submitted: #{submitted_count}; unsubmitted: #{assignments.length - submitted_count}."
    puts "If this login is new, set its password in Canvas before the first direct sign-in."
  end
end
