# frozen_string_literal: true

module Memury
  class SemesterCommandService
    def initialize(user:, now: Time.zone.now)
      @user = user
      @now = now
    end

    def create_event(attributes)
      Memury::CalendarEvent.create!(attributes.slice(
        :title, :starts_at, :ends_at, :availability
      ).merge(user:, source_kind: "personal", recurrence_rule: nil, locked: attributes[:availability] == "busy"))
    end

    def update_event(id, attributes)
      event = Memury::CalendarEvent.find_by!(id:, user:)
      payload = attributes.slice(:title, :starts_at, :ends_at, :availability).merge(recurrence_rule: nil)
      payload[:locked] = payload[:availability] == "busy" if payload[:availability].present?
      event.update!(payload)
      event
    end

    def delete_event(id)
      Memury::CalendarEvent.find_by!(id:, user:).destroy!
    end

    def update_plan_block(id, attributes)
      block = Memury::PlanBlock.find_by!(id:, user:)
      proposed = block.attributes.symbolize_keys.merge(attributes.slice(:starts_at, :ends_at, :locked, :status))
      validate_plan_window!(block, proposed)
      block.update!(attributes.slice(:starts_at, :ends_at, :locked, :status))
      block
    end

    def focus(command, attributes)
      case command
      when "start"
        raise ActiveRecord::RecordInvalid if active_focus

        Memury::FocusSession.create!(user:, course_id: attributes[:course_id], assignment_id: attributes[:assignment_id],
                                     plan_block_id: attributes[:plan_block_id], started_at: now, last_resumed_at: now)
      when "pause"
        session = active_focus!
        session.update!(active_seconds: session.elapsed_seconds(now), paused_at: now, last_resumed_at: nil, status: "paused")
        session
      when "resume"
        session = paused_focus!
        session.update!(status: "active", paused_at: nil, last_resumed_at: now)
        session
      when "finish"
        session = current_focus!
        session.update!(active_seconds: session.elapsed_seconds(now), ended_at: now, last_resumed_at: nil, status: "completed")
        session
      else
        raise ArgumentError, "unsupported focus command"
      end
    end

    def create_question(attributes)
      Memury::LearningQuestion.create!(attributes.slice(
        :content, :concept, :source_kind, :course_id, :assignment_id, :review_at
      ).merge(user:, source_kind: attributes[:source_kind].presence || "manual"))
    end

    def update_question(id, attributes)
      question = Memury::LearningQuestion.find_by!(id:, user:)
      payload = attributes.slice(:content, :concept, :status, :resolution_note, :review_at)
      payload[:resolved_at] = now if payload[:status] == "resolved"
      payload[:resolved_at] = nil if payload[:status].present? && payload[:status] != "resolved"
      question.update!(payload)
      question
    end

    private

    attr_reader :user, :now

    def validate_plan_window!(block, attributes)
      starts_at = Time.zone.parse(attributes[:starts_at].to_s)
      ends_at = Time.zone.parse(attributes[:ends_at].to_s)
      return if starts_at.blank? || ends_at.blank?

      if ends_at <= starts_at
        block.errors.add(:ends_at, "must be after starts_at")
      end

      due_at = Time.zone.parse(block.metadata["due_at"].to_s)
      block.errors.add(:ends_at, "must be before the assignment deadline") if due_at && ends_at > due_at

      conflict = Memury::CalendarEvent.where(user:, availability: "busy")
                                      .where("starts_at < ? AND ends_at > ?", ends_at, starts_at).exists?
      block.errors.add(:base, "study block overlaps a busy event") if conflict
      raise ActiveRecord::RecordInvalid, block if block.errors.any?
    rescue ArgumentError, TypeError
      block.errors.add(:base, "invalid study block time")
      raise ActiveRecord::RecordInvalid, block
    end

    def active_focus
      Memury::FocusSession.find_by(user:, status: "active")
    end

    def active_focus!
      active_focus || raise(ActiveRecord::RecordNotFound)
    end

    def paused_focus!
      Memury::FocusSession.find_by!(user:, status: "paused")
    end

    def current_focus!
      Memury::FocusSession.where(user:, status: %w[active paused]).first!
    end
  end
end
