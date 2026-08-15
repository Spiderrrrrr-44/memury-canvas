# frozen_string_literal: true

require "digest"
require "json"

class MemuryController < ApplicationController
  class LearningStateConflict < StandardError; end

  TERMINAL_BLOCK_STATUSES = %w[completed skipped].freeze
  TRACE_REQUIRED_EVENTS = %w[answer_transfer complete_block skip_block reschedule_block].freeze

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
    apply_schedule(state)
    @profile.update!(state:, last_synced_at: Time.zone.now)
    render json: present_state
  end

  def reset
    @profile.update!(state: Memury::DemoState.build, last_synced_at: Time.zone.now)
    render json: present_state
  end

  def action
    supported_events = %w[
      start_study_block
      answer_recall
      answer_verification
      request_hint
      start_transfer
      answer_transfer
      return_home
      complete_block
      skip_block
      reschedule_block
    ]
    return render json: { error: "unsupported event" }, status: :unprocessable_content unless supported_events.include?(params[:event].to_s)

    state = @profile.state.deep_dup
    before_state = state.deep_dup
    if params[:event].to_s == "answer_transfer" && duplicate_transfer_request?(state)
      return render json: present_state
    end

    begin
      # Provider calls and state calculation intentionally happen before the
      # row lock. Network latency must never hold a database transaction open.
      dispatch_event(state)

      @profile.with_lock do
        # The lock is acquired only for the final atomic persistence. Refuse
        # to overwrite a concurrent learning event calculated from an older
        # snapshot; callers can retry with a fresh state.
        raise LearningStateConflict unless @profile.state.deep_dup == before_state

        Memury::Learning::TraceRecorder.record_event!(
          user: @current_user,
          state:,
          event: params[:event].to_s,
          params:,
          before_state:,
          now: Time.zone.now,
          required: TRACE_REQUIRED_EVENTS.include?(params[:event].to_s)
        )
        @profile.update!(state:)
      end
    rescue LearningStateConflict
      return render json: { error: "learning_state_conflict" }, status: :conflict
    rescue Memury::Learning::TraceRecorder::StorageUnavailable => e
      return render json: { error: e.reason }, status: :service_unavailable
    rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
      raise unless TRACE_REQUIRED_EVENTS.include?(params[:event].to_s)

      Rails.logger.error("Memury learning transaction rolled back: #{e.class}")
      return render json: { error: "trace_storage_unavailable" }, status: :service_unavailable
    end
    render json: present_state
  end

  def replan
    state = @profile.state.deep_dup
    apply_schedule(state)
    @profile.update!(state:)
    render json: present_state
  end

  def create_event
    semester_commands.create_event(event_params)
    replan
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join("；") }, status: :unprocessable_content
  end

  def update_event
    semester_commands.update_event(params[:id], event_params)
    replan
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join("；") }, status: :unprocessable_content
  end

  def destroy_event
    semester_commands.delete_event(params[:id])
    replan
  end

  def update_plan_block
    semester_commands.update_plan_block(params[:id], plan_block_params)
    render json: present_state
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join("；") }, status: :unprocessable_content
  end

  def focus
    semester_commands.focus(params[:command], focus_params)
    render json: present_state
  end

  def create_question
    semester_commands.create_question(question_params)
    render json: present_state
  end

  def update_question
    semester_commands.update_question(params[:id], question_params)
    render json: present_state
  end

  private

  def require_memury
    render_unauthorized_action unless @domain_root_account&.feature_enabled?(:memury)
  end

  def dispatch_event(state)
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
    end
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
    catalog_by_title = Memury::DemoCourseCatalog.assignments.index_by { |item| item[:title] }
    existing_by_title = existing.index_by { |item| item["title"] }
    canvas.each do |item|
      catalog_item = catalog_by_title[item["title"]]
      existing_item = existing_by_title[item["title"]]
      demo_id = catalog_item&.fetch(:id, nil) || existing_item&.fetch("demo_assignment_id", nil)
      item["demo_assignment_id"] = demo_id.to_s if demo_id.present?
    end
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
      diagnostic_result = teaching_provider.diagnose(
        Memury::Teaching::TutorContext.from_state(state, student_answer:)
      )

      diagnostic = diagnostic_result.to_h.slice(
        "diagnosis_summary",
        "answer_judgment",
        "misconception_type",
        "evidence",
        "confidence",
        "verification_question",
        "hint",
        "transfer_question",
        "learner_state_suggestion",
        "source"
      )
      state["diagnostic"] = diagnostic
      provider_metadata = diagnostic_result.metadata if diagnostic_result.respond_to?(:metadata)
      state["diagnostic_meta"] = {
        "fallback_reason" => diagnostic_result.fallback_reason,
        "compatibility_note" => diagnostic_result.compatibility_note,
        "latency_ms" => diagnostic_result.latency_ms,
        "provider_metadata" => provider_metadata
      }.compact
      session["recall_correct"] = diagnostic_result.answer_judgment == "correct"
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
    state["guidance"] = teaching_provider.guide(Memury::Teaching::TutorContext.from_state(state)).to_h
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
    prepare_transfer_practice(state)
    state["phase"] = "transfer"
    activate_block(state, "transfer")
  end

  def update_learning_state(state)
    session = state.fetch("learning_session")
    validation = validate_transfer(state)
    session["transfer_validation"] = validation.to_h
    session["last_transfer_request_key"] = transfer_request_key(state)
    session["last_transfer_processed_at"] = Time.zone.now.iso8601
    transfer_correct = validation.verified
    concept = state.fetch("concept")
    before_confidence = concept["confidence"]
    before_plan = planning_snapshot(state)
    result = Memury::LearnerStateUpdater.call(
      current_mastery: concept.fetch("mastery"),
      diagnostic_correct: session.fetch("recall_correct", false),
      used_hint: session.fetch("used_hint", false),
      hypothesis_verified: session.fetch("hypothesis_verified", false),
      transfer_correct:,
      validated: validation.verified,
      current_confidence: concept["confidence"]
    )
    concept.merge!(result.stringify_keys)
    session["transfer_correct"] = transfer_correct
    session["evidence_summary"] = teaching_provider.summarize_evidence(
      Memury::Teaching::EvidenceContext.new(
        evidence: [
          { "kind" => "recall",
            "verified" => session.fetch("recall_correct", false),
            "validation_basis" => "legacy_demo_signal" },
          { "kind" => "hypothesis",
            "verified" => session.fetch("hypothesis_verified", false),
            "validation_basis" => session.fetch("hypothesis_verified", false) ? "deterministic_rule" : "insufficient_basis" },
          { "kind" => "transfer",
            "verified" => validation.verified,
            "validation_basis" => validation.validation_basis,
            "reason_code" => validation.reason_code,
            "hint_dependent" => validation.hint_dependent }
        ]
      )
    ).to_h
    target_id = session.fetch("target_assignment_id")
    if transfer_correct
      session["completed_at"] = Time.zone.now.iso8601
      state["completed_assignment_ids"] = (state.fetch("completed_assignment_ids", []) + [target_id]).uniq
      state["recent_activity_at"] = Time.zone.now.iso8601
      state["phase"] = "complete"
      complete_block(state, "transfer")
    else
      # A failed or legacy transfer attempt is a recorded learning event, not
      # a completed assignment. Keep the user on the transfer step so the UI
      # can offer another attempt without fabricating success.
      session.delete("completed_at")
      session["failed_at"] = Time.zone.now.iso8601
      state["phase"] = "transfer"
      activate_block(state, "transfer")
    end
    append_evidence(state, "Transfer 迁移题#{transfer_correct ? "答对" : "未通过"}")
    before_mastery = result.fetch(:previous_mastery)
    decision = {
      "at" => Time.zone.now.iso8601,
      "reason" => result[:reason],
      "change" => transfer_correct ? "掌握度 #{result[:previous_mastery]} → #{result[:mastery]}；已重排下一行动" : "验证未通过，掌握度与计划保持不变",
      "reason_code" => legacy_reason_code(validation),
      "trigger_evidence" => "transfer_validation",
      "before" => { "mastery" => before_mastery, "confidence" => before_confidence },
      "after" => { "mastery" => result[:mastery], "confidence" => result[:confidence] },
      "risk_before" => before_plan.fetch("risk"),
      "risk_after" => nil,
      "plan_before" => before_plan,
      "plan_after" => nil
    }
    replan_blocks(state) if transfer_correct
    after_plan = planning_snapshot(state)
    decision["risk_after"] = after_plan.fetch("risk")
    decision["plan_after"] = after_plan
    state["decision_logs"] << decision
  end

  def prepare_transfer_practice(state)
    practice_context = Memury::Teaching::PracticeContext.from_state(state)
    candidate = teaching_provider.generate_practice(practice_context)
    validation = teaching_provider.validate_practice(
      Memury::Teaching::ValidatorContext.for_candidate(candidate:, context: practice_context)
    )
    unless validation.verified
      fallback_provider = Memury::Teaching::DeterministicProvider.new
      candidate = fallback_provider.generate_practice(practice_context)
      validation = fallback_provider.validate_practice(
        Memury::Teaching::ValidatorContext.for_candidate(candidate:, context: practice_context)
      )
    end

    session = state.fetch("learning_session")
    session["practice_candidate"] = candidate.to_h
    session["practice_validation"] = validation.to_h
    state["diagnostic"]["transfer_question"] = candidate.prompt if validation.verified && state["diagnostic"].is_a?(Hash)
  end

  def validate_transfer(state)
    session = state.fetch("learning_session")
    candidate_payload = session["practice_candidate"].to_h
    candidate = if candidate_payload["prompt"].present? && candidate_payload["expected_answer"].present?
                  Memury::Teaching::PracticeCandidate.new(
                    id: candidate_payload["id"],
                    prompt: candidate_payload["prompt"],
                    expected_answer: candidate_payload["expected_answer"],
                    explanation: candidate_payload["explanation"],
                    knowledge_point: candidate_payload["knowledge_point"],
                    difficulty: candidate_payload["difficulty"],
                    source: candidate_payload["source"]
                  )
                else
                  context = Memury::Teaching::PracticeContext.from_state(state)
                  teaching_provider.generate_practice(context)
                end
    context = Memury::Teaching::PracticeContext.from_state(state)
    legacy_correct = params.key?(:correct) ? ActiveModel::Type::Boolean.new.cast(params[:correct]) : nil
    answer = params[:student_answer].presence || params[:transfer_answer].presence || ""
    teaching_provider.assess_transfer(
      Memury::Teaching::ValidatorContext.for_transfer(
        candidate:, context:, student_answer: answer, legacy_correct:, hint_dependent: session.fetch("used_hint", false)
      )
    )
  end

  def legacy_reason_code(validation)
    return "legacy_demo_answer_failed" if validation.reason_code == "legacy_demo_signal" && !params[:correct].to_s.casecmp("true").zero?

    validation.reason_code
  end

  def duplicate_transfer_request?(state)
    session = state.fetch("learning_session", {})
    session["last_transfer_request_key"].present? && session["last_transfer_request_key"] == transfer_request_key(state)
  end

  def transfer_request_key(state)
    session = state.fetch("learning_session", {})
    payload = {
      "candidate_id" => session.dig("practice_candidate", "id"),
      "student_answer" => params[:student_answer].to_s,
      "transfer_answer" => params[:transfer_answer].to_s,
      "correct" => params[:correct].to_s,
      "hint_level" => session.fetch("hint_level", 0)
    }
    Digest::SHA256.hexdigest(JSON.generate(payload))
  end

  def planning_snapshot(state)
    all_ranked = Memury::RiskEngine.call(
      assignments: state.fetch("assignments", []),
      sis_events: state.fetch("sis_events", []),
      concept: state.fetch("concept"),
      recent_activity_at: state["recent_activity_at"],
      completed_assignment_ids: state.fetch("completed_assignment_ids", [])
    )
    next_assignment = ranked_assignments(state).first
    target_id = state.dig("learning_session", "target_assignment_id").to_s
    target = all_ranked.find { |assignment| assignment["id"].to_s == target_id }
    {
      "next_assignment_id" => next_assignment&.fetch("id", nil),
      "next_risk" => next_assignment&.fetch("risk", nil),
      "risk" => target&.fetch("risk", nil),
      "study_blocks" => state.fetch("study_blocks", []).map do |block|
        block.slice("id", "stage", "status", "starts_at", "duration_minutes")
      end
    }
  end

  def teaching_provider
    @teaching_provider ||= Memury::Teaching::ProviderRegistry.current
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
    evidence_state = Memury::EvidenceSignalProjector.call(user: @current_user, state:)
    state["hint_catalog_size"] = HINTS.length
    public_state = Memury::PublicStateBuilder.call(state: evidence_state, context: state_context)
    semester = Memury::SemesterStateBuilder.call(user: @current_user, state: evidence_state)
    Memury::PublicStateSerializer.call(public_state.merge("semester_memory" => semester))
  end

  def presentable_assignments(state)
    Memury::RiskEngine.call(
      assignments: state.fetch("assignments", []), sis_events: state.fetch("sis_events", []),
      concept: state.fetch("concept", {}), recent_activity_at: state["recent_activity_at"],
      completed_assignment_ids: state.fetch("completed_assignment_ids", [])
    )
  end

  def apply_schedule(state)
    result = Memury::Scheduler.call(user: @current_user, assignments: presentable_assignments(state))
    state["planning_status"] = {
      "status" => result.blocks.any? ? "planned" : "no_available_time",
      "generated_count" => result.blocks.length,
      "unscheduled" => result.unscheduled,
      "updated_at" => Time.zone.now.iso8601
    }
    result
  end

  def semester_commands
    @semester_commands ||= Memury::SemesterCommandService.new(user: @current_user)
  end

  def event_params
    params.permit(:title, :starts_at, :ends_at, :availability).to_h.symbolize_keys
  end

  def plan_block_params
    params.permit(:starts_at, :ends_at, :locked, :status).to_h.symbolize_keys
  end

  def focus_params
    params.permit(:course_id, :assignment_id, :plan_block_id).to_h.symbolize_keys
  end

  def question_params
    params.permit(
      :content, :concept, :source_kind, :course_id, :assignment_id, :review_at, :status, :resolution_note
    ).to_h.symbolize_keys
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
