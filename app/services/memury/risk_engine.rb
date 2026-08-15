# frozen_string_literal: true

module Memury
  class RiskEngine
    WINDOW_HOURS = 7.days.in_hours

    def self.call(assignments:, sis_events:, concept:, recent_activity_at:, completed_assignment_ids:, now: Time.zone.now)
      new(assignments:, sis_events:, concept:, recent_activity_at:, completed_assignment_ids:, now:).call
    end

    def initialize(assignments:, sis_events:, concept:, recent_activity_at:, completed_assignment_ids:, now:)
      @assignments = assignments
      @sis_events = sis_events
      @concept = concept
      @recent_activity_at = recent_activity_at
      @completed_assignment_ids = completed_assignment_ids.map(&:to_s)
      @now = now
    end

    def call
      assignments.map { |assignment| score(assignment.with_indifferent_access) }
                 .sort_by { |assignment| -assignment["risk"] }
    end

    private

    attr_reader :assignments, :sis_events, :concept, :recent_activity_at, :completed_assignment_ids, :now

    def score(assignment)
      due_at = parse_optional_time(assignment[:due_at])
      overdue = due_at.present? && due_at < now
      hours_left = due_at.present? ? [((due_at - now) / 1.hour), 0].max : nil
      deadline = due_at.blank? ? 0.05 : (1.0 - (hours_left / WINDOW_HOURS)).clamp(0.05, 1.0)
      unsubmitted = assignment[:submitted] ? 0.0 : 1.0
      exam = assignment.fetch(:exam_relevance, nearby_exam?(assignment[:course_id]) ? 0.6 : 0.1).to_f.clamp(0.0, 1.0)
      mastery = assignment.fetch(:evidence_mastery, concept.fetch("mastery", concept.fetch(:mastery, 0.5)))
      weakness = 1.0 - mastery.to_f.clamp(0.0, 1.0)
      inactivity = activity_risk
      risk = (deadline * 0.32) + (unsubmitted * 0.24) + (exam * 0.2) + (weakness * 0.19) + (inactivity * 0.05)
      completed = completed_assignment_ids.include?(assignment[:id].to_s)
      risk *= 0.35 if completed

      assignment.to_h.stringify_keys.merge(
        "risk" => risk.round(2),
        "risk_reasons" => reasons(hours_left:, overdue:, due_missing: due_at.blank?, unsubmitted:, exam:, weakness:, inactivity:, completed:)
      )
    end

    def reasons(hours_left:, overdue:, due_missing:, unsubmitted:, exam:, weakness:, inactivity:, completed:)
      return ["已完成本轮补强，风险已显著下降"] if completed

      [].tap do |items|
        items << "作业已逾期，当前仍未提交" if overdue && unsubmitted.positive?
        items << "作业将在 #{hours_left.ceil} 小时内截止" if !overdue && !due_missing && hours_left <= 72
        items << "Canvas 暂未提供截止时间" if due_missing
        items << "Canvas 显示尚未提交" if unsubmitted.positive?
        items << "三天内有相关考试" if exam >= 0.6
        items << "对应知识点掌握度偏低" if weakness >= 0.45
        items << "近三天学习活动不足" if inactivity >= 0.6
        items << "当前风险较低，按原计划推进" if items.empty?
      end
    end

    def activity_risk
      observed_at = parse_time(recent_activity_at)
      (((now - observed_at) / 3.days).clamp(0.0, 1.0)).round(2)
    end

    def nearby_exam?(course_id)
      sis_events.any? do |event|
        item = event.with_indifferent_access
        same_course = item[:course_id].blank? || course_id.blank? || item[:course_id].to_s == course_id.to_s
        item[:exam] && same_course && parse_time(item[:starts_at]).between?(now, now + 7.days)
      end
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) || now
    rescue ArgumentError, TypeError
      now
    end

    def parse_optional_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
