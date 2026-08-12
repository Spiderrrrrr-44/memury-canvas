# frozen_string_literal: true

module Memury
  class FocusSession < ApplicationRecord
    self.table_name = "memury_focus_sessions"

    belongs_to :user
    belongs_to :course, optional: true
    belongs_to :assignment, optional: true
    belongs_to :plan_block, class_name: "Memury::PlanBlock", optional: true

    enum :status, [:active, :paused, :completed], prefix: true

    validates :status, :started_at, presence: true

    def elapsed_seconds(now = Time.zone.now)
      active_seconds + (status_active? && last_resumed_at ? (now - last_resumed_at).to_i : 0)
    end
  end
end
