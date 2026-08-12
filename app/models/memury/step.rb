# frozen_string_literal: true

module Memury
  class Step < ApplicationRecord
    self.table_name = "memury_learning_steps"

    belongs_to :session, class_name: "Memury::Session", foreign_key: :learning_session_id, inverse_of: :steps
    has_many :evidences, class_name: "Memury::Evidence", dependent: :nullify, inverse_of: :step

    validates :kind, :sequence, :idempotency_key, :started_at, presence: true
    validates :sequence, uniqueness: { scope: :learning_session_id }
    validates :idempotency_key, uniqueness: { scope: :learning_session_id }
  end
end
