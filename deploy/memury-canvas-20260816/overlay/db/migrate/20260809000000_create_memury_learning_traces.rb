# frozen_string_literal: true

class CreateMemuryLearningTraces < ActiveRecord::Migration[8.0]
  tag :predeploy

  def change
    create_table :memury_learning_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: true, foreign_key: true
      t.references :assignment, null: true, foreign_key: true
      t.string :course_ref
      t.string :assignment_ref
      t.string :study_block_id
      t.string :objective, null: false
      t.string :status, null: false, default: "active"
      t.string :result
      t.text :summary
      t.string :idempotency_key, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :duration_seconds
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :memury_learning_sessions, :idempotency_key, unique: true
    add_index :memury_learning_sessions, [:user_id, :status]

    create_table :memury_learning_steps do |t|
      t.references :learning_session, null: false, foreign_key: { to_table: :memury_learning_sessions }
      t.string :kind, null: false
      t.integer :sequence, null: false
      t.string :status, null: false, default: "completed"
      t.string :idempotency_key, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.jsonb :input, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.timestamps
    end
    add_index :memury_learning_steps, [:learning_session_id, :sequence], unique: true
    add_index :memury_learning_steps, [:learning_session_id, :idempotency_key], unique: true,
              name: "index_memury_steps_on_session_and_idempotency"

    create_table :memury_learning_evidence do |t|
      t.references :learning_session, null: false, foreign_key: { to_table: :memury_learning_sessions }
      t.references :learning_step, null: true, foreign_key: { to_table: :memury_learning_steps }
      t.string :kind, null: false
      t.string :fingerprint, null: false
      t.string :source, null: false
      t.boolean :verified, null: false, default: false
      t.decimal :confidence, precision: 4, scale: 3
      t.datetime :observed_at, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :memury_learning_evidence, [:learning_session_id, :fingerprint], unique: true,
              name: "index_memury_evidence_on_session_and_fingerprint"
    add_index :memury_learning_evidence, [:learning_session_id, :verified]
  end
end
