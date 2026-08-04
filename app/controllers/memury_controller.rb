# frozen_string_literal: true

class MemuryController < ApplicationController
  before_action :require_user
  before_action :require_memury
  before_action :load_profile

  def index
    @page_title = t("Memury")
    js_bundle :memury
    js_env MEMURY: { demo_mode: demo_mode?, api_url: memury_state_path }
    render html: "<div id=\"memury-root\"></div>".html_safe, layout: true
  end

  def state
    render json: present_state
  end

  def sync
    canvas = Memury::Connectors::CanvasNativeConnector.new(user: @current_user).call
    current = @profile.state.presence || Memury::DemoState.build
    merged = current.merge("canvas" => canvas, "sis_events" => Memury::Connectors::DemoSisConnector.new(user: @current_user).call,
                           "last_synced_at" => Time.zone.now.iso8601)
    merged["assignments"] = canvas[:assignments] if canvas[:assignments].length >= 5
    @profile.update!(state: merged, last_synced_at: Time.zone.now)
    render json: present_state
  end

  def action
    state = @profile.state.deep_dup
    case params[:event]
    when "answer_diagnostic"
      state["phase"] = "verify"
      state["hypotheses"] = [{ name: "概念混淆", confidence: 0.61 }, { name: "读题错误", confidence: 0.25 }, { name: "计算失误", confidence: 0.14 }]
    when "answer_verification"
      state["phase"] = "intervention"
      state["verified_hypothesis"] = "概念混淆：未区分力的受力物体"
    when "request_hint"
      state["hint_level"] = [state.fetch("hint_level", 0) + 1, 4].min
    when "answer_transfer"
      update_learning_state(state)
    when "complete_block", "skip_block"
      block = find_block(state)
      block["status"] = params[:event] == "complete_block" ? "completed" : "skipped" if block
    when "reschedule_block"
      block = find_block(state)
      if block
        block["starts_at"] = Time.zone.parse(params[:starts_at].to_s)&.iso8601
        block["duration_minutes"] = params[:duration_minutes].to_i.clamp(10, 180)
        block["official_or_inferred"] = "User override"
      end
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
      profile.state = Memury::DemoState.build if demo_mode?
    end
  end

  def demo_mode?
    ENV.fetch("MEMURY_DEMO_MODE", "true") == "true"
  end

  def find_block(state)
    state.fetch("study_blocks", []).find { |item| item["id"] == params[:block_id] }
  end

  def update_learning_state(state)
    concept = state.fetch("concept")
    result = Memury::LearnerStateUpdater.call(current_mastery: concept.fetch("mastery"), diagnostic_correct: false,
                                               used_hint: state.fetch("hint_level", 0).positive?, hypothesis_verified: true,
                                               transfer_correct: ActiveModel::Type::Boolean.new.cast(params[:correct]))
    concept.merge!(result.stringify_keys)
    state["phase"] = "complete"
    state["evidence"] << { "title" => "跨情境迁移题#{params[:correct] ? '答对' : '未通过'}", "source" => "Memury 学习会话", "observed_at" => Time.zone.now.iso8601 }
    state["decision_logs"] << { "at" => Time.zone.now.iso8601, "reason" => result[:reason], "change" => "掌握度 #{result[:previous_mastery]} → #{result[:mastery]}" }
    state.fetch("study_blocks", []).each_with_index do |block, index|
      block["starts_at"] = (Time.zone.now + (index + 1).days + 18.hours).iso8601 if block["status"] == "planned"
    end
  end

  def present_state
    state = @profile.state.deep_dup
    assignment = state.fetch("assignments", []).max_by { |item| item["risk"].to_f }
    state["next_action"] = {
      "title" => assignment&.fetch("title", "受力分析作业 2"), "course" => assignment&.fetch("course_name", "工程力学基础"),
      "priority" => Memury::PriorityScorer.call(exam_relevance: 0.95, weakness: 0.78, forgetting_risk: 0.82, expected_gain: 0.74, time_cost: 25),
      "why" => "该知识点属于三天后考试重点；最近相关作答失败；任务将在 36 小时内截止；预计 25 分钟可完成一次有效补强。"
    }
    state
  end
end
