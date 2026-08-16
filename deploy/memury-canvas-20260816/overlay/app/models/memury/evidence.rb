# frozen_string_literal: true

module Memury
  class Evidence < ApplicationRecord
    self.table_name = "memury_learning_evidence"

    belongs_to :session, class_name: "Memury::Session", foreign_key: :learning_session_id, inverse_of: :evidences
    belongs_to :step, class_name: "Memury::Step", optional: true, foreign_key: :learning_step_id, inverse_of: :evidences

    validates :kind, :fingerprint, :source, :observed_at, presence: true
    validates :fingerprint, uniqueness: { scope: :learning_session_id }
  end
end
