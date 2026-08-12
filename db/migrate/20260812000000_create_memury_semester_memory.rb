# frozen_string_literal: true

class CreateMemurySemesterMemory < ActiveRecord::Migration[8.0]
  tag :predeploy

  def change
    create_table :memury_academic_evidence do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: true, foreign_key: true
      t.references :assignment, null: true, foreign_key: true
      t.string :kind, null: false
      t.string :source_kind, null: false
      t.string :source_ref, null: false
      t.string :title, null: false
      t.text :summary
      t.string :concept
      t.string :error_pattern
      t.boolean :verified, null: false, default: false
      t.decimal :confidence, precision: 4, scale: 3
      t.datetime :observed_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :memury_academic_evidence, [:user_id, :source_kind, :source_ref], unique: true,
              name: "index_memury_academic_evidence_on_source"
    add_index :memury_academic_evidence, [:user_id, :verified, :observed_at],
              name: "index_memury_academic_evidence_on_verification"

    create_table :memury_calendar_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: true, foreign_key: true
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :source_kind, null: false, default: "personal"
      t.string :availability, null: false, default: "busy"
      t.string :recurrence_rule
      t.boolean :locked, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :memury_calendar_events, [:user_id, :starts_at]

    create_table :memury_plan_blocks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: true, foreign_key: true
      t.references :assignment, null: true, foreign_key: true
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :status, null: false, default: "planned"
      t.boolean :locked, null: false, default: false
      t.text :reason, null: false
      t.string :source_kind, null: false, default: "scheduler"
      t.integer :sequence, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :memury_plan_blocks, [:user_id, :starts_at]

    create_table :memury_focus_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: true, foreign_key: true
      t.references :assignment, null: true, foreign_key: true
      t.references :plan_block, null: true, foreign_key: { to_table: :memury_plan_blocks }
      t.string :status, null: false, default: "active"
      t.datetime :started_at, null: false
      t.datetime :paused_at
      t.datetime :ended_at
      t.integer :active_seconds, null: false, default: 0
      t.datetime :last_resumed_at
      t.timestamps
    end
    add_index :memury_focus_sessions, [:user_id, :status]

    create_table :memury_learning_questions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: true, foreign_key: true
      t.references :assignment, null: true, foreign_key: true
      t.text :content, null: false
      t.string :concept
      t.string :source_kind, null: false
      t.string :status, null: false, default: "open"
      t.text :resolution_note
      t.datetime :review_at
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :memury_learning_questions, [:user_id, :status]
  end
end
