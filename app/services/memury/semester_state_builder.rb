# frozen_string_literal: true

module Memury
  class SemesterStateBuilder
    def self.call(user:, state:, now: Time.zone.now)
      new(user:, state:, now:).call
    end

    def initialize(user:, state:, now:)
      @user = user
      @state = state
      @now = now
    end

    def call
      evidence = Memury::EvidenceAdapter.call(user:, state:)
      {
        "evidence" => evidence,
        "evidence_summary" => evidence_summary(evidence),
        "calendar_events" => calendar_events,
        "plan_blocks" => plan_blocks,
        "focus" => focus_summary,
        "questions" => questions,
        "trends" => trends(evidence)
      }
    end

    private

    attr_reader :user, :state, :now

    def evidence_summary(evidence)
      verified = evidence.select { |item| item["verified"] }
      {
        "verified_count" => verified.length,
        "inferred_count" => evidence.length - verified.length,
        "quality" => verified.empty? ? "insufficient" : "supported",
        "mastery_basis" => verified.empty? ? "证据不足，暂不生成精确掌握度" : "仅由已验证的 Canvas / Demo Evidence 支持"
      }
    end

    def calendar_events
      Memury::CalendarEvent.where(user:).where(starts_at: (now - 1.day)..(now + 14.days)).order(:starts_at).map do |event|
        {
          "id" => event.id.to_s, "title" => event.title, "starts_at" => event.starts_at.iso8601,
          "ends_at" => event.ends_at.iso8601, "source_kind" => event.source_kind,
          "availability" => event.availability, "recurrence_rule" => event.recurrence_rule,
          "locked" => event.locked, "course_id" => event.course_id&.to_s
        }.compact
      end
    end

    def plan_blocks
      Memury::PlanBlock.where(user:).where(starts_at: (now - 1.day)..(now + 14.days)).order(:starts_at).map do |block|
        {
          "id" => block.id.to_s, "title" => block.title, "starts_at" => block.starts_at.iso8601,
          "ends_at" => block.ends_at.iso8601, "status" => block.status, "locked" => block.locked,
          "reason" => block.reason, "source_kind" => block.source_kind, "sequence" => block.sequence,
          "course_id" => block.course_id&.to_s, "assignment_id" => block.assignment_id&.to_s
        }.compact
      end
    end

    def focus_summary
      sessions = Memury::FocusSession.where(user:).where(started_at: (now - 30.days)..now).order(started_at: :desc)
      active = sessions.find { |item| !item.status_completed? }
      {
        "active" => active && focus_payload(active),
        "today_seconds" => sessions.select { |item| item.started_at.to_date == now.to_date }.sum { |item| item.elapsed_seconds(now) },
        "week_seconds" => sessions.select { |item| item.started_at >= now.beginning_of_week }.sum { |item| item.elapsed_seconds(now) },
        "month_seconds" => sessions.sum { |item| item.elapsed_seconds(now) },
        "recent" => sessions.first(8).map { |item| focus_payload(item) }
      }
    end

    def focus_payload(item)
      {
        "id" => item.id.to_s, "status" => item.status, "started_at" => item.started_at.iso8601,
        "ended_at" => item.ended_at&.iso8601, "active_seconds" => item.elapsed_seconds(now),
        "course_id" => item.course_id&.to_s, "assignment_id" => item.assignment_id&.to_s,
        "plan_block_id" => item.plan_block_id&.to_s
      }.compact
    end

    def questions
      Memury::LearningQuestion.where(user:).order(created_at: :desc).map do |item|
        {
          "id" => item.id.to_s, "content" => item.content, "concept" => item.concept,
          "source_kind" => item.source_kind, "status" => item.status,
          "resolution_note" => item.resolution_note, "review_at" => item.review_at&.iso8601,
          "created_at" => item.created_at.iso8601, "course_id" => item.course_id&.to_s,
          "assignment_id" => item.assignment_id&.to_s
        }.compact
      end
    end

    def trends(evidence)
      verified = evidence.select { |item| item["verified"] }
      {
        "has_sufficient_evidence" => verified.length >= 3,
        "evidence_by_course" => verified.group_by { |item| item["course_id"] || "unassigned" }.transform_values(&:length),
        "repeated_error_patterns" => verified.filter_map { |item| item["error_pattern"] }.tally,
        "open_question_count" => Memury::LearningQuestion.where(user:, status: %w[open investigating]).count,
        "planned_minutes" => Memury::PlanBlock.where(user:, starts_at: now.beginning_of_week..now.end_of_week).sum("EXTRACT(EPOCH FROM (ends_at - starts_at)) / 60").to_i,
        "actual_focus_minutes" => Memury::FocusSession.where(user:, started_at: now.beginning_of_week..now.end_of_week).sum(:active_seconds).to_i / 60
      }
    end
  end
end
