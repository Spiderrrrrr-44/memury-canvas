# frozen_string_literal: true

module Memury
  class LearningQuestion < ApplicationRecord
    self.table_name = "memury_learning_questions"

    belongs_to :user
    belongs_to :course, optional: true
    belongs_to :assignment, optional: true

    enum :status, [:open, :investigating, :resolved], prefix: true

    validates :content, :source_kind, :status, presence: true
  end
end
