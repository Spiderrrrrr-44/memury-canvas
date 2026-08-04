# frozen_string_literal: true

class CreateMemuryLearnerProfiles < ActiveRecord::Migration[8.0]
  tag :predeploy

  def change
    create_table :memury_learner_profiles do |t|
      t.references :user, null: false, index: { unique: true }, foreign_key: true
      t.jsonb :state, null: false, default: {}
      t.datetime :last_synced_at
      t.timestamps
    end
  end
end
