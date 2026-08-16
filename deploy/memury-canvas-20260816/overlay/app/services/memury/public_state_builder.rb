# frozen_string_literal: true

require "time"

module Memury
  # Builds the one public, deterministic learning view used by every Memury
  # surface.  It deliberately only derives recommendations from persisted
  # Canvas/SIS provenance and LearnerProfile state; it never calls an AI
  # provider.
  class PublicStateBuilder
    CONTEXT_TYPES = %w[dashboard course assignment page module session].freeze

    def self.call(state:, context: {}, now: Time.zone.now)
      new(state:, context:, now:).call
    end

    def initialize(state:, context:, now:)
      @state = state.deep_stringify_keys
      @context = context.to_h.deep_stringify_keys
      @now = now
      @course_ids = {}
    end

    def call
      assignments = ranked_assignments.map { |assignment| add_course_id(assignment) }
      courses = build_courses(assignments)
      next_action = build_next_action(assignments)
      today_blocks = build_today_blocks
      risks = build_risks(assignments)

      state.merge(
        "time_zone" => Time.zone.tzinfo.name,
        "assignments" => assignments,
        "today" => build_today(today_blocks),
        "academic_snapshot" => build_academic_snapshot(assignments, courses, risks),
        "next_action" => next_action,
        "study_blocks" => today_blocks.map { |item| item.except("today_status") },
        "risks" => risks,
        "courses" => courses,
        "learner_state" => build_learner_state,
        "recent_evidence" => state.fetch("evidence", []).last(6).reverse,
        "agent_activity" => build_agent_activity(next_action),
        "current_context" => build_current_context(assignments, next_action),
        "provenance" => {
          "generated_at" => @now.iso8601,
          "state_source" => "Learner State + Canvas/SIS/Demo",
          "official_or_inferred" => "Inferred"
        }
      )
    end

    private

    attr_reader :state

    def ranked_assignments
      Memury::RiskEngine.call(
        assignments: state.fetch("assignments", []),
        sis_events: state.fetch("sis_events", []),
        concept: state.fetch("concept", {}),
        recent_activity_at: state["recent_activity_at"],
        completed_assignment_ids: state.fetch("completed_assignment_ids", []),
        now: @now
      )
    end

    def add_course_id(assignment)
      item = assignment.stringify_keys
      canvas_course = state.fetch("canvas", {}).fetch("courses", []).map(&:stringify_keys).find do |course|
        course["name"].to_s.casecmp(item["course_name"].to_s).zero?
      end
      item["course_id"] = canvas_course["id"].to_s if canvas_course
      item["course_id"] ||= course_id_for(item["course_name"])
      item
    end

    def course_id_for(course_name)
      return "memury-course-unknown" if course_name.blank?

      @course_ids[course_name] ||= begin
        known = {
          "工程力学基础" => "demo-course-mechanics",
          "程序设计实践" => "demo-course-programming"
        }
        known[course_name] || "memury-course-#{@course_ids.length + 1}"
      end
    end

    def build_courses(assignments)
      groups = assignments.group_by { |assignment| assignment["course_id"] }
      canvas_courses = state.fetch("canvas", {}).fetch("courses", []).map(&:stringify_keys)
      canvas_courses.each do |course|
        groups[course["id"].to_s] ||= []
      end

      groups.map do |course_id, course_assignments|
        course_name = course_assignments.first&.fetch("course_name", nil) ||
                      canvas_courses.find { |course| course["id"].to_s == course_id.to_s }&.fetch("name", nil) ||
                      course_id.to_s
        course_blocks = state.fetch("study_blocks", []).select do |block|
          block["course_id"].to_s == course_id.to_s || block["course_name"] == course_name
        end
        next_action = build_next_action(course_assignments, apply_context: false)
        source = provenance_for(course_assignments, canvas_courses, course_id)

        {
          "id" => course_id.to_s,
          "name" => course_name,
          "source" => source,
          "official_or_inferred" => source["official_or_inferred"],
          "risk" => course_assignments.map { |item| item["risk"].to_f }.max || 0.0,
          "risk_reasons" => course_assignments.flat_map { |item| item.fetch("risk_reasons", []) }.uniq.first(4),
          "assignment_count" => course_assignments.length,
          "incomplete_count" => course_assignments.count { |item| incomplete_assignment?(item) },
          "estimated_minutes" => course_assignments.sum { |item| item.fetch("estimated_minutes", 0).to_i },
          "upcoming_exam" => upcoming_exam_for(course_name, course_id),
          "weak_concepts" => weak_concepts_for(course_name),
          "recent_evidence" => recent_evidence_for(course_name),
          "next_action" => next_action,
          "study_blocks" => course_blocks
        }
      end.sort_by { |course| -course["risk"].to_f }
    end

    def provenance_for(assignments, canvas_courses, course_id)
      assignment = assignments.first
      canvas_course = canvas_courses.find { |course| course["id"].to_s == course_id.to_s }
      if assignment&.fetch("official_or_inferred", nil) == "Official" || canvas_course
        {
          "source_platform" => "Canvas",
          "source_object_id" => (canvas_course || assignment).fetch("id").to_s,
          "official_or_inferred" => "Official",
          "confidence" => 1.0
        }
      else
        {
          "source_platform" => "Demo Canvas data",
          "source_object_id" => course_id.to_s,
          "official_or_inferred" => "Simulated",
          "confidence" => 1.0
        }
      end
    end

    def build_next_action(assignments, apply_context: true)
      scoped = apply_context ? target_assignments(assignments) : assignments
      target = actionable_assignments(scoped).first
      return nil unless target

      evidence = evidence_for(target)
      {
        "assignment_id" => target.fetch("id").to_s,
        "title" => target.fetch("title"),
        "course" => target.fetch("course_name"),
        "course_id" => target.fetch("course_id").to_s,
        "priority" => target.fetch("risk", 0).to_f,
        "reasons" => target.fetch("risk_reasons", []),
        "why" => target.fetch("risk_reasons", []).join("；"),
        "reason" => target.fetch("risk_reasons", []).join("；"),
        "estimated_minutes" => target.fetch("estimated_minutes", 25).to_i,
        "confidence" => target.fetch("confidence", 0.5).to_f,
        "source" => {
          "type" => "risk_engine",
          "id" => target.fetch("id").to_s,
          "platform" => target.fetch("source_platform", "Memury"),
          "official_or_inferred" => target.fetch("official_or_inferred", "Inferred")
        },
        "evidence" => evidence,
        "generated_at" => @now.iso8601
      }
    end

    def target_assignments(assignments)
      course_id = @context["course_id"].presence
      assignment_id = @context["assignment_id"].presence
      scoped = assignments
      scoped = scoped.select { |item| item["course_id"].to_s == course_id.to_s } if course_id
      scoped = scoped.select { |item| item["id"].to_s == assignment_id.to_s } if assignment_id
      return scoped if course_id || assignment_id

      scoped
    end

    def actionable_assignments(assignments)
      completed_ids = state.fetch("completed_assignment_ids", []).map(&:to_s)
      assignments.reject do |assignment|
        due_at = assignment_due_at(assignment)
        assignment["submitted"] || completed_ids.include?(assignment["id"].to_s) || (due_at && due_at < @now)
      end
    end

    def evidence_for(assignment)
      evidence = [
        {
          "type" => "assignment",
          "id" => assignment.fetch("id").to_s,
          "label" => assignment.fetch("title"),
          "source" => assignment.fetch("source_platform", "Canvas"),
          "official_or_inferred" => assignment.fetch("official_or_inferred", "Inferred")
        },
        {
          "type" => "learner_state",
          "id" => concept_id,
          "label" => "#{assignment["concept"].presence || state.dig("concept", "name")} · 掌握度 #{((assignment["evidence_mastery"] || state.dig("concept", "mastery")).to_f * 100).round}%",
          "source" => "Learner State",
          "official_or_inferred" => "Inferred"
        }
      ]
      exam = upcoming_exam_for(assignment["course_name"], assignment["course_id"])
      if exam
        provenance = event_provenance(exam)
        evidence << {
          "type" => "exam",
          "id" => exam["id"].to_s,
          "label" => exam["title"],
          "source" => provenance["source_platform"] || "SIS",
          "official_or_inferred" => provenance["official_or_inferred"] || "Simulated"
        }
      end
      evidence
    end

    def build_risks(assignments)
      assignment_risks = assignments.map do |assignment|
        {
          "type" => "assignment",
          "id" => assignment.fetch("id").to_s,
          "course_id" => assignment.fetch("course_id").to_s,
          "course" => assignment.fetch("course_name"),
          "title" => assignment.fetch("title"),
          "due_at" => assignment["due_at"],
          "status" => assignment_status(assignment),
          "risk" => assignment.fetch("risk", 0).to_f,
          "reasons" => assignment.fetch("risk_reasons", []),
          "estimated_minutes" => assignment.fetch("estimated_minutes", 25).to_i,
          "source" => assignment_provenance(assignment)
        }
      end
      exam_risks = upcoming_exams.map do |exam|
        provenance = event_provenance(exam)
        starts_at = parse_time(exam["starts_at"])
        hours_left = [(starts_at - @now) / 1.hour, 0].max
        {
          "type" => "exam",
          "id" => exam.fetch("id").to_s,
          "course_id" => course_id_for(exam["title"].to_s.sub(/模拟考试.*/, "")),
          "course" => exam["title"].to_s.sub(/模拟考试.*/, ""),
          "title" => exam.fetch("title"),
          "starts_at" => exam.fetch("starts_at"),
          "status" => ((hours_left <= 72) ? "due_soon" : "upcoming"),
          "risk" => (1.0 - (hours_left / 168.0)).clamp(0.05, 1.0).round(2),
          "reasons" => ["距离考试约 #{hours_left.ceil} 小时", "考试来自 #{provenance["source_platform"] || "SIS"}"],
          "estimated_minutes" => 30,
          "source" => provenance.merge("official_or_inferred" => provenance["official_or_inferred"] || "Simulated")
        }
      end
      concept_risk = build_concept_risk
      (assignment_risks + exam_risks + [concept_risk].compact).sort_by { |item| -item["risk"].to_f }
    end

    def build_concept_risk
      concept = state.fetch("concept", {})
      name = concept["name"].presence
      return unless name

      assignment = state.fetch("assignments", []).find { |item| item["concept"] == name }
      course_name = assignment&.fetch("course_name", nil) || concept["course_name"] || "Learner State"
      mastery = concept.fetch("mastery", 0.5).to_f.clamp(0.0, 1.0)
      {
        "type" => "concept",
        "id" => concept_id,
        "course_id" => assignment&.fetch("course_id", nil) || course_id_for(course_name),
        "course" => course_name,
        "title" => name,
        "status" => (mastery < 0.6 ? "review_needed" : "monitor"),
        "risk" => (1.0 - mastery).round(2),
        "reasons" => ["Learner State 当前掌握度 #{(mastery * 100).round}%", concept["misconception"]].compact,
        "estimated_minutes" => 15,
        "source" => {
          "source_platform" => "Learner State",
          "source_object_id" => concept_id,
          "official_or_inferred" => "Inferred",
          "confidence" => concept.fetch("confidence", 0.5).to_f
        }
      }
    end

    def assignment_provenance(assignment)
      assignment.slice("source_platform", "source_object_id", "source_url", "official_or_inferred", "confidence")
    end

    def build_today_blocks
      state.fetch("study_blocks", []).map(&:stringify_keys).sort_by { |block| parse_time(block["starts_at"]) }.map do |block|
        status = block["status"]
        block.merge("today_status" => if status == "completed"
                                        "completed"
                                      elsif status == "active"
                                        "current"
                                      else
                                        "upcoming"
                                      end)
      end
    end

    def build_today(blocks)
      {
        "date" => @now.to_date.iso8601,
        "study_blocks" => blocks,
        "total_minutes" => blocks.sum { |block| block.fetch("duration_minutes", 0).to_i },
        "completed_minutes" => blocks.select { |block| block["status"] == "completed" }.sum { |block| block.fetch("duration_minutes", 0).to_i },
        "has_overdue" => overdue_assignments.any?,
        "has_due_soon" => due_soon_assignments.any?,
        "has_schedule_conflict" => schedule_conflict?(blocks)
      }
    end

    def build_academic_snapshot(assignments, courses, risks)
      {
        "course_count" => courses.length,
        "incomplete_assignment_count" => assignments.count { |item| incomplete_assignment?(item) },
        "due_soon_count" => due_soon_assignments(assignments).length,
        "overdue_count" => overdue_assignments(assignments).length,
        "upcoming_exam_count" => upcoming_exams.length,
        "overall_risk" => risks.map { |item| item["risk"].to_f }.max.to_f.round(2),
        "weekly_estimated_minutes" => assignments.select do |item|
          due_at = assignment_due_at(item)
          due_at && due_at >= @now && due_at <= @now + 7.days && incomplete_assignment?(item)
        end.sum { |item| item.fetch("estimated_minutes", 0).to_i }
      }
    end

    def build_learner_state
      concept = state.fetch("concept", {})
      {
        "weak_concepts" => [{
          "id" => concept_id,
          "name" => concept["name"],
          "mastery" => concept["mastery"],
          "confidence" => concept["confidence"],
          "misconception" => concept["misconception"],
          "source" => "Learner State",
          "official_or_inferred" => "Inferred"
        }],
        "mastery_change" => {
          "previous" => concept["previous_mastery"],
          "current" => concept["mastery"],
          "reason" => concept["reason"]
        },
        "recent_activity_at" => state["recent_activity_at"],
        "completed_sessions" => state["learning_session"].to_h["completed_at"].present? ? 1 : 0,
        "recent_evidence" => state.fetch("evidence", []).last(3).reverse
      }
    end

    def build_agent_activity(next_action)
      logs = state.fetch("decision_logs", []).last(5).reverse.map do |log|
        log.merge("type" => "decision", "source" => "Memury Risk Engine", "official_or_inferred" => "Inferred")
      end
      if next_action
        logs.unshift(
          "type" => "recommendation",
          "at" => next_action["generated_at"],
          "reason" => next_action["reason"],
          "source" => "Memury Risk Engine",
          "official_or_inferred" => "Inferred"
        )
      end
      logs
    end

    def build_current_context(assignments, next_action)
      course_id = @context["course_id"].presence
      assignment_id = @context["assignment_id"].presence
      selected = assignments.find { |item| item["id"].to_s == assignment_id.to_s } if assignment_id
      selected ||= assignments.find { |item| item["course_id"].to_s == course_id.to_s } if course_id
      relationship_to_plan = if selected && next_action && selected["id"].to_s == next_action["assignment_id"].to_s
                               "当前推荐行动"
                             else
                               "已纳入风险队列"
                             end
      {
        "type" => CONTEXT_TYPES.include?(@context["type"]) ? @context["type"] : "dashboard",
        "course_id" => course_id || selected&.fetch("course_id", nil),
        "course_name" => selected&.fetch("course_name", nil),
        "assignment_id" => assignment_id,
        "assignment_title" => selected&.fetch("title", nil),
        "relationship_to_plan" => relationship_to_plan
      }.compact
    end

    def weak_concepts_for(course_name)
      concept_course = state.dig("concept", "course_name")
      return [] if concept_course.present? && concept_course != course_name
      return [] unless state.fetch("assignments", []).any? { |item| item["course_name"] == course_name && item["concept"] == state.dig("concept", "name") }

      build_learner_state.fetch("weak_concepts")
    end

    def recent_evidence_for(course_name)
      return [] unless weak_concepts_for(course_name).any?

      state.fetch("evidence", []).last(3).reverse
    end

    def upcoming_exam_for(course_name, course_id = nil)
      course_key = course_name.to_s.split(":", 2).first
      upcoming_exams.find do |exam|
        (course_id.present? && exam["course_id"].to_s == course_id.to_s) ||
          exam["title"].to_s.start_with?(course_name.to_s) ||
          (course_key.present? && exam["title"].to_s.start_with?(course_key))
      end
    end

    def event_provenance(event)
      nested = event["provenance"]
      return nested.stringify_keys if nested.is_a?(Hash)

      event.slice("source_platform", "source_object_id", "source_url", "last_synced_at", "official_or_inferred", "confidence")
    end

    def upcoming_exams
      @upcoming_exams ||= state.fetch("sis_events", []).map(&:stringify_keys).select { |event| event["exam"] }
    end

    def due_soon_assignments(assignments = state.fetch("assignments", []))
      assignments.select do |assignment|
        due_at = assignment_due_at(assignment)
        incomplete_assignment?(assignment) && due_at && due_at >= @now && due_at <= @now + 72.hours
      end
    end

    def overdue_assignments(assignments = state.fetch("assignments", []))
      assignments.select do |assignment|
        due_at = assignment_due_at(assignment)
        incomplete_assignment?(assignment) && due_at && due_at < @now
      end
    end

    def assignment_status(assignment)
      return "completed" if state.fetch("completed_assignment_ids", []).map(&:to_s).include?(assignment["id"].to_s)
      return "submitted" if assignment["submitted"]
      due_at = assignment_due_at(assignment)
      return "no_due_date" unless due_at
      return "overdue" if due_at < @now
      return "due_soon" if due_at <= @now + 72.hours

      "upcoming"
    end

    def incomplete_assignment?(assignment)
      !assignment["submitted"] && !state.fetch("completed_assignment_ids", []).map(&:to_s).include?(assignment["id"].to_s)
    end

    def schedule_conflict?(blocks)
      blocks.combination(2).any? do |left, right|
        left_start = parse_time(left["starts_at"])
        right_start = parse_time(right["starts_at"])
        left_end = left_start + left.fetch("duration_minutes", 0).to_i.minutes
        right_end = right_start + right.fetch("duration_minutes", 0).to_i.minutes
        left_start < right_end && right_start < left_end
      end
    end

    def concept_id
      @concept_id ||= state.dig("concept", "name").to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-$/, "").presence || "concept-1"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) || @now
    rescue ArgumentError, TypeError
      @now
    end

    def assignment_due_at(assignment)
      value = assignment["due_at"]
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
