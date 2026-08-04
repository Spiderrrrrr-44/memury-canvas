# frozen_string_literal: true

namespace :memury do
  desc "Enable Memury and initialize deterministic demo state for a Canvas user (LOGIN=...)"
  task demo_seed: :environment do
    login = ENV.fetch("LOGIN", "memury.student@example.test")
    account = Account.default
    account.enable_feature!(:memury)
    pseudonym = Pseudonym.active.find_by(account:, unique_id: login)
    abort "Create the Canvas user #{login.inspect} first, then rerun this task." unless pseudonym

    profile = Memury::LearnerProfile.find_or_initialize_by(user: pseudonym.user)
    profile.state = Memury::DemoState.build
    profile.last_synced_at = Time.zone.now
    profile.save!
    puts "Memury demo initialized for #{login}; feature flag enabled on account #{account.id}."
  end
end
