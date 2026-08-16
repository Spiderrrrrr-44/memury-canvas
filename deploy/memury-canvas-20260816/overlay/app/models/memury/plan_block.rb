# frozen_string_literal: true

module Memury
  class PlanBlock < ApplicationRecord
    self.table_name = "memury_plan_blocks"

    belongs_to :user
    belongs_to :course, optional: true
    belongs_to :assignment, optional: true

    enum :status, [:planned, :completed, :skipped], prefix: true

    validates :title, :starts_at, :ends_at, :status, :reason, :source_kind, presence: true
    validate :ends_after_start

    private

    def ends_after_start
      errors.add(:ends_at, "must be after starts_at") if starts_at && ends_at && ends_at <= starts_at
    end
  end
end
