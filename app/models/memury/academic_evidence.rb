# frozen_string_literal: true

module Memury
  class AcademicEvidence < ApplicationRecord
    self.table_name = "memury_academic_evidence"

    belongs_to :user
    belongs_to :course, optional: true
    belongs_to :assignment, optional: true

    validates :kind, :source_kind, :source_ref, :title, :observed_at, presence: true
    validates :source_ref, uniqueness: { scope: [:user_id, :source_kind] }

    scope :verified, -> { where(verified: true) }
  end
end
