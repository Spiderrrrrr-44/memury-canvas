# frozen_string_literal: true

module Memury
  class SemesterCommandService
    def initialize(user:, now: Time.zone.now)
      @user = user
      @now = now
    end

    def create_event(attributes)
      Memury::CalendarEvent.create!(attributes.slice(
        :title, :starts_at, :ends_at, :availability, :recurrence_rule, :locked, :course_id
      ).merge(user:, source_kind: attributes[:source_kind].presence || "personal"))
    end

    def update_event(id, attributes)
      event = Memury::CalendarEvent.find_by!(id:, user:)
      event.update!(attributes.slice(:title, :starts_at, :ends_at, :availability, :recurrence_rule, :locked))
      event
    end

    def delete_event(id)
      Memury::CalendarEvent.find_by!(id:, user:).destroy!
    end

    def update_plan_block(id, attributes)
      block = Memury::PlanBlock.find_by!(id:, user:)
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
