# frozen_string_literal: true

class MemuryController < ApplicationController
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
    when "reschedule_block"
      reschedule_block(state)
    else
      return render json: { error: "unsupported event" }, status: :unprocessable_entity
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
    state["phase"] = "recall"
    state["learning_session"] = {
      "target_assignment_id" => target_id.to_s,
      "started_at" => Time.zone.now.iso8601,
      "used_hint" => false,
      "hint_level" => 0
    }
    activate_block(state, "recall")
  end

  def answer_recall(state)
    correct = ActiveModel::Type::Boolean.new.cast(params[:correct])
    session = state.fetch("learning_session")
    session["recall_correct"] = correct
    complete_block(state, "recall")
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
    state["verified_hypothesis"] = "概念混淆：未区分力的受力物体"
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
    append_evidence(state, "Transfer 迁移题#{transfer_correct ? '答对' : '未通过'}")
    state["decision_logs"] << {
      "at" => Time.zone.now.iso8601,
      "reason" => result[:reason],
      "change" => "掌握度 #{result[:previous_mastery]} → #{result[:mastery]}；已重排下一行动"
    }
    replan_blocks(state)
  end

  def update_requested_block(state)
    block = find_block(state, params[:block_id])
    block["status"] = params[:event] == "complete_block" ? "completed" : "skipped" if block
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
    block = state.fetch("study_blocks", []).find { |item| item["stage"] == stage }
    block["status"] = "active" if block
  end

  def complete_block(state, stage)
    block = state.fetch("study_blocks", []).find { |item| item["stage"] == stage }
    block["status"] = "completed" if block
  end

  def append_evidence(state, title)
    state["evidence"] << { "title" => title, "source" => "Memury learning session", "observed_at" => Time.zone.now.iso8601 }
  end

  def replan_blocks(state)
    state.fetch("study_blocks", []).each_with_index do |block, index|
      next if block["status"] == "completed"

      block["starts_at"] = (Time.zone.now + 1.day + (index * 15).minutes).iso8601
    end
  end

  def ranked_assignments(state)
    Memury::RiskEngine.call(
      assignments: state.fetch("assignments", []),
      sis_events: state.fetch("sis_events", []),
      concept: state.fetch("concept"),
      recent_activity_at: state["recent_activity_at"],
      completed_assignment_ids: state.fetch("completed_assignment_ids", [])
    )
  end

  def present_state
    state = @profile.state.deep_dup
    ranked = ranked_assignments(state)
    state["assignments"] = ranked
    next_assignment = ranked.first
    state["next_action"] = if next_assignment
                             {
                               "assignment_id" => next_assignment.fetch("id").to_s,
                               "title" => next_assignment.fetch("title"),
                               "course" => next_assignment.fetch("course_name"),
                               "priority" => next_assignment.fetch("risk"),
                               "reasons" => next_assignment.fetch("risk_reasons"),
                               "why" => next_assignment.fetch("risk_reasons").join("；"),
                               "estimated_minutes" => next_assignment.fetch("estimated_minutes", 25)
                             }
                           end
    state["hint_catalog_size"] = HINTS.length
    state
  end
end
