# frozen_string_literal: true

class MemuryController < ApplicationController
  TERMINAL_BLOCK_STATUSES = %w[completed skipped].freeze

  HINTS = [
    "先分别标出每个力作用在哪个物体上。",
    "平衡力必须作用在同一个物体上；作用力与反作用力作用在不同物体上。",
    "比较‘桌面对书的支持力’与‘书对桌面的压力’，检查它们的受力物体。",
    "完整结论：支持力与压力是一对作用力—反作用力，不是作用在同一物体上的平衡力。"
  ].freeze

  before_action :require_user
  before_action :require_memury
  before_action :load_profile

  def index
    @page_title = t("Memury")
    js_bundle :memury
    js_env({ MEMURY: { demo_mode: demo_mode?, api_url: memury_state_path } })
    render html: "<div id=\"memury-root\"></div>".html_safe, layout: true
  end

  def state
    render json: present_state
  end

  def sync
    canvas = Memury::Connectors::CanvasNativeConnector.new(user: @current_user).call
    state = @profile.state.presence || Memury::DemoState.build
    state["canvas"] = canvas
    state["sis_events"] = Memury::Connectors::DemoSisConnector.new(user: @current_user).call
    state["assignments"] = merge_assignments(state.fetch("assignments", []), canvas[:assignments])
    state["last_synced_at"] = Time.zone.now.iso8601
    state["sync_summary"] = { "courses" => canvas[:courses].length, "assignments" => canvas[:assignments].length }
    @profile.update!(state:, last_synced_at: Time.zone.now)
    render json: present_state
  end

  def reset
    @profile.update!(state: Memury::DemoState.build, last_synced_at: Time.zone.now)
    render json: present_state
  end

  def action
    state = @profile.state.deep_dup
    case params[:event]
    when "start_study_block"
      start_study_block(state)
    when "answer_recall"
      answer_recall(state)
    when "answer_verification"
      answer_verification(state)
    when "request_hint"
      request_hint(state)
    when "start_transfer"
      start_transfer(state)
    when "answer_transfer"
      update_learning_state(state)
    when "return_home"
      state["phase"] = "overview"
    when "complete_block", "skip_block"
      update_requested_block(state)
      replan_blocks(state)
    when "reschedule_block"
      reschedule_block(state)
      replan_blocks(state)
    else
      return render json: { error: "unsupported event" }, status: :unprocessable_content
    end

    @profile.update!(state:)
    render json: present_state
  end

  private

  def require_memury
    render_unauthorized_action unless @domain_root_account&.feature_enabled?(:memury)
  end

  def load_profile
    @profile = Memury::LearnerProfile.find_or_create_by!(user: @current_user) do |profile|
      profile.state = Memury::DemoState.build
    end
  end

  def demo_mode?
    ENV.fetch("MEMURY_DEMO_MODE", "true") == "true"
  end

  def merge_assignments(existing, canvas_assignments)
    canvas = canvas_assignments.map(&:stringify_keys)
    official_titles = canvas.pluck("title").to_set
    simulated = existing.select do |item|
      item["official_or_inferred"] == "Simulated" && !official_titles.include?(item["title"])
    end
    (canvas + simulated).uniq do |item|
      [item["source_platform"], item["source_object_id"]]
    end
  end

  def start_study_block(state)
    target_id = params[:assignment_id].presence || ranked_assignments(state).first&.fetch("id", nil)
    target = state.fetch("assignments", []).find { |item| item["id"].to_s == target_id.to_s }
    target_id = target&.fetch("id", nil) || ranked_assignments(state).first&.fetch("id", nil)
    source_types = %w[next_best_action today_study_block course_weak_concept dashboard course assignment assistant]
    source_type = params[:source_type].to_s
    state["phase"] = "recall"
    state["learning_session"] = {
      "target_assignment_id" => target_id.to_s,
      "started_at" => Time.zone.now.iso8601,
      "used_hint" => false,
      "hint_level" => 0,
      "recall_question" => state.dig("learning_session", "recall_question") || recall_question,
      "source_type" => source_types.include?(source_type) ? source_type : "next_best_action",
      "source_id" => params[:source_id].presence || target_id.to_s,
      "course_id" => params[:course_id].presence || target&.fetch("course_id", nil),
      "concept_id" => params[:concept_id].presence || concept_identifier(state),
      "trigger_reason" => params[:trigger_reason].to_s.truncate(240).presence || "风险排序后的下一最佳行动",
      "originating_study_block" => params[:originating_study_block].presence
    }
    activate_block(state, "recall")
  end

  def answer_recall(state)
    session = state.fetch("learning_session")
    complete_block(state, "recall")
    student_answer = params[:student_answer].to_s.strip

    if student_answer.present?
      diagnostic_result = Memury::Ai::TeachingDiagnosisService.call(
        course_or_subject: current_course_or_subject(state),
        knowledge_point: state.fetch("concept").fetch("name"),
        question: session.fetch("recall_question", recall_question),
        scoring_basis: state.dig("concept", "reference_answer"),
        student_answer:,
        learner_state_summary: learner_state_summary(state)
      )

      diagnostic = diagnostic_result.diagnostic.merge(
        "source" => diagnostic_result.source,
        "answer_judgment" => diagnostic_result.diagnostic["answer_judgment"]
      )
      state["diagnostic"] = diagnostic
      state["diagnostic_meta"] = {
        "fallback_reason" => diagnostic_result.fallback_reason,
        "compatibility_note" => diagnostic_result.compatibility_note,
        "latency_ms" => diagnostic_result.latency_ms
      }.compact
      session["recall_correct"] = diagnostic.fetch("answer_judgment") == "correct"
      state["hypotheses"] = hypotheses_from_diagnostic(diagnostic)
      state["phase"] = "verify"
      append_evidence(state, "自由回答诊断：#{diagnostic.fetch("diagnosis_summary")}")
      return
    end

    correct = ActiveModel::Type::Boolean.new.cast(params[:correct])
    session["recall_correct"] = correct
    append_evidence(state, correct ? "Recall 基础检查答对" : "Recall 暴露概念混淆")

    if correct
      state["phase"] = "transfer"
      activate_block(state, "transfer")
    else
      state["phase"] = "verify"
      state["hypotheses"] = [
        { "name" => "概念混淆", "confidence" => 0.61 },
        { "name" => "读题错误", "confidence" => 0.25 },
        { "name" => "计算失误", "confidence" => 0.14 }
      ]
    end
  end

  def answer_verification(state)
    state["phase"] = "repair"
    state["verified_hypothesis"] = state.dig("diagnostic", "diagnosis_summary").presence || "概念混淆：未区分力的受力物体"
    state.fetch("learning_session")["hypothesis_verified"] = true
    activate_block(state, "repair")
  end

  def request_hint(state)
    session = state.fetch("learning_session")
    level = [session.fetch("hint_level", 0) + 1, HINTS.length].min
    session["hint_level"] = level
    session["used_hint"] = true
    session["active_hint"] = HINTS[level - 1]
  end

  def start_transfer(state)
    complete_block(state, "repair")
    state["phase"] = "transfer"
    activate_block(state, "transfer")
  end

  def update_learning_state(state)
    session = state.fetch("learning_session")
    transfer_correct = ActiveModel::Type::Boolean.new.cast(params[:correct])
    concept = state.fetch("concept")
    result = Memury::LearnerStateUpdater.call(
      current_mastery: concept.fetch("mastery"),
      diagnostic_correct: session.fetch("recall_correct", false),
      used_hint: session.fetch("used_hint", false),
      hypothesis_verified: session.fetch("hypothesis_verified", false),
      transfer_correct:
    )
    concept.merge!(result.stringify_keys)
    session["transfer_correct"] = transfer_correct
    session["completed_at"] = Time.zone.now.iso8601
    target_id = session.fetch("target_assignment_id")
    state["completed_assignment_ids"] = (state.fetch("completed_assignment_ids", []) + [target_id]).uniq
    state["recent_activity_at"] = Time.zone.now.iso8601
    state["phase"] = "complete"
    complete_block(state, "transfer")
    append_evidence(state, "Transfer 迁移题#{transfer_correct ? "答对" : "未通过"}")
    state["decision_logs"] << {
      "at" => Time.zone.now.iso8601,
      "reason" => result[:reason],
      "change" => "掌握度 #{result[:previous_mastery]} → #{result[:mastery]}；已重排下一行动"
    }
    replan_blocks(state)
  end

  def update_requested_block(state)
    block = find_block(state, params[:block_id])
    block["status"] = ((params[:event] == "complete_block") ? "completed" : "skipped") if block
  end

  def reschedule_block(state)
    block = find_block(state, params[:block_id])
    return unless block

    starts_at = Time.zone.parse(params[:starts_at].to_s)
    block["starts_at"] = starts_at.iso8601 if starts_at
    block["duration_minutes"] = params[:duration_minutes].to_i.clamp(10, 180)
    block["official_or_inferred"] = "User override"
  rescue ArgumentError
    nil
  end

  def find_block(state, id)
    state.fetch("study_blocks", []).find { |item| item["id"] == id }
  end

  def activate_block(state, stage)
    block = state.fetch("study_blocks", []).find do |item|
      item["stage"] == stage && !TERMINAL_BLOCK_STATUSES.include?(item["status"])
    end
    block["status"] = "active" if block
  end

  def complete_block(state, stage)
    block = state.fetch("study_blocks", []).find do |item|
      item["stage"] == stage && !TERMINAL_BLOCK_STATUSES.include?(item["status"])
    end
    block["status"] = "completed" if block
  end

  def append_evidence(state, title)
    session = state.fetch("learning_session", {})
    state["evidence"] << {
      "title" => title,
      "source" => "Memury learning session",
      "source_type" => session["source_type"],
      "source_id" => session["source_id"],
      "course_id" => session["course_id"],
      "concept_id" => session["concept_id"],
      "official_or_inferred" => "Inferred",
      "observed_at" => Time.zone.now.iso8601
    }.compact
  end

  def hypotheses_from_diagnostic(diagnostic)
    confidence = diagnostic.fetch("confidence", 0.5).to_f
    [
      { "name" => diagnostic.fetch("misconception_type"), "confidence" => confidence.round(2) },
      { "name" => "读题错误", "confidence" => (1.0 - confidence).clamp(0.0, 1.0).round(2) },
      { "name" => "计算失误", "confidence" => [0.14, (1.0 - confidence) / 2].max.round(2) }
    ]
  end

  def recall_question
    "一本书静止在桌面上。桌面对书的支持力与书对桌面的压力是一对平衡力吗？"
  end

  def current_course_or_subject(state)
    state.dig("assignments", 0, "course_name").presence ||
      state.dig("canvas", "courses", 0, "name").presence ||
      "工程力学基础"
  end

  def learner_state_summary(state)
    concept = state.fetch("concept")
    target_assignment = state.dig("learning_session", "target_assignment_id")
    target = state.fetch("assignments", []).find { |item| item["id"].to_s == target_assignment.to_s }

    {
      "knowledge_point" => concept["name"],
      "mastery" => concept["mastery"],
      "recent_activity_at" => state["recent_activity_at"],
      "completed_assignments" => state.fetch("completed_assignment_ids", []).length,
      "active_assignment" => target&.slice("title", "course_name", "due_at", "submitted", "estimated_minutes"),
      "evidence_count" => state.fetch("evidence", []).length
    }.compact
  end

  def concept_identifier(state)
    state.dig("concept", "name").to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-$/, "").presence || "concept-1"
  end

  def replan_blocks(state)
    blocks = state.fetch("study_blocks", [])
    blocks.each_with_index do |block, index|
      next if block["status"] == "completed"

      block["starts_at"] = Time.zone.now.advance(days: 1, minutes: index * 15).iso8601
    end

    return unless state.dig("learning_session", "completed_at").present?
    return if blocks.any? { |block| !TERMINAL_BLOCK_STATUSES.include?(block["status"]) }

    next_assignment = ranked_assignments(state).first
    return unless next_assignment
    return if blocks.any? do |block|
      block["source_type"] == "replan" && block["source_id"].to_s == next_assignment["id"].to_s
    end

    concept = next_assignment["concept"].presence || state.dig("concept", "name") || "待巩固概念"
    course_name = next_assignment["course_name"].presence || "未命名课程"
    base_time = Time.zone.now.advance(days: 1)
    stages = [
      ["recall", "Recall：回忆 #{concept}", 10],
      ["repair", "Repair：检查 #{concept}", 15],
      ["transfer", "Transfer：迁移 #{concept}", 10]
    ]
    stages.each_with_index do |(stage, title, duration), index|
      blocks << {
        "id" => "block-#{next_assignment.fetch("id")}-#{stage}",
        "stage" => stage,
        "title" => title,
        "starts_at" => base_time.advance(minutes: index * 15).iso8601,
        "duration_minutes" => duration,
        "status" => "planned",
        "course_id" => next_assignment["course_id"],
        "course_name" => course_name,
        "concept" => concept,
        "source_type" => "replan",
        "source_id" => next_assignment.fetch("id").to_s,
        "trigger_reason" => "上一学习 session 完成后，根据新的风险排序重排",
        "official_or_inferred" => "Inferred",
        "source_platform" => "Memury Risk Engine",
        "source_object_id" => "block-#{next_assignment.fetch("id")}-#{stage}",
        "last_synced_at" => Time.zone.now.iso8601,
        "confidence" => 0.86
      }
    end
  end

  def ranked_assignments(state)
    ranked = Memury::RiskEngine.call(
      assignments: state.fetch("assignments", []),
      sis_events: state.fetch("sis_events", []),
      concept: state.fetch("concept"),
      recent_activity_at: state["recent_activity_at"],
      completed_assignment_ids: state.fetch("completed_assignment_ids", [])
    )
    completed_ids = state.fetch("completed_assignment_ids", []).map(&:to_s)
    ranked.reject do |assignment|
      assignment["submitted"] || completed_ids.include?(assignment["id"].to_s)
    end
  end

  def present_state
    state = @profile.state.deep_dup
    state["hint_catalog_size"] = HINTS.length
    public_state = Memury::PublicStateBuilder.call(state:, context: state_context)
    Memury::PublicStateSerializer.call(public_state)
  end

  def state_context
    {
      "type" => params[:context_type].presence || "dashboard",
      "course_id" => params[:course_id].presence,
      "assignment_id" => params[:assignment_id].presence,
      "page_id" => params[:page_id].presence,
      "module_id" => params[:module_id].presence
    }.compact
  end
end
