# frozen_string_literal: true

module Memury
  class CalendarEvent < ApplicationRecord
    self.table_name = "memury_calendar_events"

    belongs_to :user
    belongs_to :course, optional: true

    enum :availability, [:busy, :flexible], prefix: true

    validates :title, :starts_at, :ends_at, :source_kind, :availability, presence: true
    validate :ends_after_start

    private

    def ends_after_start
      errors.add(:ends_at, "must be after starts_at") if starts_at && ends_at && ends_at <= starts_at
    end
  end
end
