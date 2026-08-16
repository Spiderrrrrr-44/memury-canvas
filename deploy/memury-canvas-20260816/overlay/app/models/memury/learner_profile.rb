# frozen_string_literal: true

module Memury
  class LearnerProfile < ApplicationRecord
    self.table_name = "memury_learner_profiles"

    belongs_to :user
    validates :user_id, uniqueness: true
  end
end
