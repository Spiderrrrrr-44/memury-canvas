# frozen_string_literal: true

module Memury
  class Session < ApplicationRecord
    self.table_name = "memury_learning_sessions"

    belongs_to :user
    belongs_to :course, optional: true
    belongs_to :assignment, optional: true
    has_many :steps, class_name: "Memury::Step", foreign_key: :learning_session_id, dependent: :destroy, inverse_of: :session
    has_many :evidences, class_name: "Memury::Evidence", foreign_key: :learning_session_id, dependent: :destroy, inverse_of: :session

    validates :objective, :status, :idempotency_key, :started_at, presence: true
    validates :idempotency_key, uniqueness: true
  end
end
