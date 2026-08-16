# frozen_string_literal: true

module Memury
  class CalendarEvent < ApplicationRecord
    self.table_name = "memury_calendar_events"

    belongs_to :user
    belongs_to :course, optional: true

    enum :availability, [:busy, :flexible], prefix: true

    validates :title, :starts_at, :ends_at, :source_kind, :availability, presence: true
    validate :ends_after_start
    validate :not_an_obvious_duplicate

    private

    def ends_after_start
      errors.add(:ends_at, "must be after starts_at") if starts_at && ends_at && ends_at <= starts_at
    end

    def not_an_obvious_duplicate
      return unless user_id && title.present? && starts_at && ends_at

      duplicate = self.class.where(user_id:, title:, starts_at:, ends_at:)
      duplicate = duplicate.where.not(id:) if persisted?
      errors.add(:base, "duplicate calendar event") if duplicate.exists?
    end
  end
end
