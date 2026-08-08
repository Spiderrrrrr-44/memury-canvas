# frozen_string_literal: true

require "spec_helper"
require "securerandom"

describe MemuryController do
  before do
    Account.default.enable_feature!(:memury)
    @user = user_factory
    user_session(@user)
  end

  def recursive_key_paths(value, target_key, path = [], matches = [])
    case value
    when Hash
      value.each do |key, nested|
        current_path = path + [key.to_s]
        matches << current_path.join(".") if key.to_s == target_key
        recursive_key_paths(nested, target_key, current_path, matches)
      end
    when Array
      value.each_with_index do |nested, index|
        recursive_key_paths(nested, target_key, path + [index.to_s], matches)
      end
    end
    matches
  end

  def expect_public_state_to_hide_sensitive_data(payload, marker)
    expect(recursive_key_paths(payload, "reference_answer")).to be_empty
    expect(recursive_key_paths(payload, "provider_prompt")).to be_empty
    expect(recursive_key_paths(payload, "provider_raw_body")).to be_empty
    expect(recursive_key_paths(payload, "stack_trace")).to be_empty
    expect(recursive_key_paths(payload, "authorization")).to be_empty
    expect(JSON.generate(payload)).not_to include(marker)
  end

  it "persists the complete Recall, Repair, and Transfer loop" do
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")

    patch :action, params: { event: "start_study_block", assignment_id: target_id }, format: :json
    expect(response.parsed_body.fetch("phase")).to eq("recall")

    patch :action, params: { event: "answer_recall", correct: false }, format: :json
    expect(response.parsed_body.fetch("phase")).to eq("verify")
    expect(response.parsed_body.fetch("hypotheses").length).to eq(3)

    patch :action, params: { event: "answer_verification" }, format: :json
    patch :action, params: { event: "request_hint" }, format: :json
    expect(response.parsed_body.dig("learning_session", "active_hint")).to be_present

    patch :action, params: { event: "start_transfer" }, format: :json
    patch :action, params: { event: "answer_transfer", correct: true }, format: :json
    completed = response.parsed_body

    expect(completed.fetch("phase")).to eq("complete")
    expect(completed.dig("concept", "mastery")).to be > initial.dig("concept", "mastery")
    expect(completed.fetch("assignments").find { |item| item["id"].to_s == target_id }.fetch("risk_reasons")).to include("已完成本轮补强，风险已显著下降")

    get :state, format: :json
    expect(response.parsed_body.fetch("phase")).to eq("complete")
  end

  it "returns to overview after completion without dropping the completed session or replanned public state" do
    post :reset, format: :json
    target_id = response.parsed_body.fetch("next_action").fetch("assignment_id")

    patch :action, params: { event: "start_study_block", assignment_id: target_id }, format: :json
    patch :action, params: { event: "answer_recall", correct: false }, format: :json
    patch :action, params: { event: "answer_verification" }, format: :json
    patch :action, params: { event: "start_transfer" }, format: :json
    patch :action, params: { event: "answer_transfer", correct: true }, format: :json

    completed = response.parsed_body
    completed_mastery = completed.dig("concept", "mastery")
    completed_evidence_count = completed.fetch("evidence").length

    patch :action, params: { event: "return_home" }, format: :json
    returned = response.parsed_body

    expect(returned.fetch("phase")).to eq("overview")
    expect(returned.dig("concept", "mastery")).to eq(completed_mastery)
    expect(returned.fetch("evidence").length).to eq(completed_evidence_count)
    expect(returned.fetch("next_action")).to be_present
    expect(returned.fetch("study_blocks")).to all(include("stage", "status"))
    expect(returned.fetch("learning_session")).to include("target_assignment_id", "transfer_correct", "completed_at")
  end

  it "resets the persisted demo to its deterministic initial state" do
    post :reset, format: :json
    patch :action, params: { event: "start_study_block", assignment_id: "mech-force" }, format: :json
    patch :action, params: { event: "answer_recall", correct: false }, format: :json

    post :reset, format: :json
    reset = response.parsed_body

    expect(reset.fetch("phase")).to eq("overview")
    expect(reset.dig("concept", "mastery")).to eq(0.42)
    expect(reset.fetch("completed_assignment_ids")).to be_empty
  end

  it "keeps reference answers and provider internals on the server while stripping them from every public state response" do
    secret = "memury-secret-#{SecureRandom.hex(8)}"
    public_state = Memury::DemoState.build.deep_stringify_keys.deep_merge(
      "concept" => {
        "reference_answer" => secret
      },
      "diagnostic" => {
        "provider_prompt" => "prompt #{secret}",
        "provider_raw_body" => "body #{secret}",
        "provider_response" => {
          "stack_trace" => "trace #{secret}"
        }
      }
    )
    allow(Memury::DemoState).to receive(:build).and_return(public_state)

    canvas_connector = instance_double(
      Memury::Connectors::CanvasNativeConnector,
      call: {
        courses: [],
        assignments: [],
        synced_at: Time.zone.now.iso8601
      }
    )
    allow(Memury::Connectors::CanvasNativeConnector).to receive(:new).and_return(canvas_connector)

    sis_connector = instance_double(Memury::Connectors::DemoSisConnector, call: [])
    allow(Memury::Connectors::DemoSisConnector).to receive(:new).and_return(sis_connector)

    post :reset, format: :json
    reset = response.parsed_body
    expect_public_state_to_hide_sensitive_data(reset, secret)
    expect(reset.fetch("concept").keys).to include("name", "mastery", "confidence", "misconception")
    profile = Memury::LearnerProfile.find_by!(user: @user)
    expect(profile.reload.state.dig("concept", "reference_answer")).to eq(secret)
    expect(profile.reload.state.dig("diagnostic", "provider_prompt")).to include(secret)

    get :state, format: :json
    state = response.parsed_body
    expect_public_state_to_hide_sensitive_data(state, secret)

    post :sync, format: :json
    sync = response.parsed_body
    expect_public_state_to_hide_sensitive_data(sync, secret)

    patch :action, params: { event: "start_study_block", assignment_id: sync.fetch("next_action").fetch("assignment_id") }, format: :json
    expect_public_state_to_hide_sensitive_data(response.parsed_body, secret)

    diagnosis = {
      "diagnosis_summary" => "学生把不同物体上的力误当作同一物体上的平衡力。",
      "answer_judgment" => "incorrect",
      "misconception_type" => "conceptual",
      "evidence" => ["把支持力和压力混为一谈"],
      "confidence" => 0.84,
      "verification_question" => "请说明为什么这两个力不能算作平衡力。",
      "hint" => "先分清作用对象，再判断是否在同一个物体上。",
      "transfer_question" => "如果换成电梯里的人与地面相互作用，这个判断会怎么变？",
      "learner_state_suggestion" => {
        "skill" => "平衡力与作用力—反作用力的区别",
        "suggested_status" => "review_needed",
        "reason" => "概念证据不足，先做最小验证再迁移。"
      }
    }
    diagnosis_result = instance_double(
      Memury::Ai::TeachingDiagnosisService::Result,
      diagnostic: diagnosis,
      source: "ai",
      fallback_reason: nil,
      compatibility_note: nil,
      latency_ms: 12
    )
    allow(Memury::Ai::TeachingDiagnosisService).to receive(:call).and_return(diagnosis_result)

    patch :action, params: { event: "answer_recall", student_answer: "我觉得它们是平衡力，因为方向相反。" }, format: :json
    expect_public_state_to_hide_sensitive_data(response.parsed_body, secret)

    patch :action, params: { event: "answer_verification" }, format: :json
    expect_public_state_to_hide_sensitive_data(response.parsed_body, secret)

    patch :action, params: { event: "request_hint" }, format: :json
    expect_public_state_to_hide_sensitive_data(response.parsed_body, secret)

    patch :action, params: { event: "start_transfer" }, format: :json
    expect_public_state_to_hide_sensitive_data(response.parsed_body, secret)

    patch :action, params: { event: "answer_transfer", correct: true }, format: :json
    completed = response.parsed_body
    expect_public_state_to_hide_sensitive_data(completed, secret)
    expect(completed.fetch("phase")).to eq("complete")
    expect(completed.fetch("study_blocks")).to all(include("stage", "status"))
    expect(completed.fetch("learning_session")).to include("target_assignment_id", "transfer_correct")
    expect(Memury::LearnerProfile.find_by!(user: @user).reload.state.dig("concept", "reference_answer")).to eq(secret)
  end

  it "prefers a real Canvas assignment over a same-title simulated fallback" do
    connector = instance_double(
      Memury::Connectors::CanvasNativeConnector,
      call: {
        courses: [{ id: 42, name: "工程力学基础（Memury Demo）" }],
        assignments: [{
          id: 101,
          course_id: 42,
          course_name: "工程力学基础（Memury Demo）",
          title: "受力分析作业 2",
          due_at: 36.hours.from_now.iso8601,
          submitted: false,
          source_platform: "Canvas",
          source_object_id: 101,
          official_or_inferred: "Official",
          confidence: 1.0
        }],
        synced_at: Time.zone.now.iso8601
      }
    )
    allow(Memury::Connectors::CanvasNativeConnector).to receive(:new).and_return(connector)

    post :reset, format: :json
    post :sync, format: :json

    matching = response.parsed_body.fetch("assignments").select { |item| item["title"] == "受力分析作业 2" }
    expect(matching.length).to eq(1)
    expect(matching.first).to include("source_platform" => "Canvas", "official_or_inferred" => "Official")
  end

  it "stores a schema-validated AI diagnosis for a free-form recall answer" do
    diagnosis = {
      "diagnosis_summary" => "学生把不同物体上的力误当作同一物体上的平衡力。",
      "answer_judgment" => "incorrect",
      "misconception_type" => "conceptual",
      "evidence" => ["把支持力和压力混为一谈"],
      "confidence" => 0.84,
      "verification_question" => "请说明为什么这两个力不能算作平衡力。",
      "hint" => "先分清作用对象，再判断是否在同一个物体上。",
      "transfer_question" => "如果换成电梯里的人与地面相互作用，这个判断会怎么变？",
      "learner_state_suggestion" => {
        "skill" => "平衡力与作用力—反作用力的区别",
        "suggested_status" => "review_needed",
        "reason" => "概念证据不足，先做最小验证再迁移。"
      }
    }
    result = instance_double(
      Memury::Ai::TeachingDiagnosisService::Result,
      diagnostic: diagnosis,
      source: "ai",
      fallback_reason: nil,
      compatibility_note: nil,
      latency_ms: 12
    )
    allow(Memury::Ai::TeachingDiagnosisService).to receive(:call).and_return(result)

    post :reset, format: :json
    patch :action, params: { event: "answer_recall", student_answer: "我觉得它们是平衡力，因为方向相反。" }, format: :json

    payload = response.parsed_body
    expect(payload.fetch("phase")).to eq("verify")
    expect(payload.dig("diagnostic", "source")).to eq("ai")
    expect(payload.dig("diagnostic", "diagnosis_summary")).to include("平衡力")
    expect(payload.dig("learning_session", "recall_correct")).to be(false)
    expect(payload.dig("diagnostic_meta", "latency_ms")).to eq(12)
  end

  it "returns the shared planning surfaces and persists the source of a learning launch" do
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")

    expect(initial).to include("today", "academic_snapshot", "risks", "courses", "learner_state", "current_context")
    expect(initial.dig("next_action", "evidence")).to be_present
    expect(initial.dig("courses", 0, "official_or_inferred")).to eq("Simulated")

    patch :action,
          params: {
            event: "start_study_block",
            assignment_id: target_id,
            source_type: "course_weak_concept",
            source_id: "concept-1",
            course_id: "demo-course-mechanics",
            concept_id: "concept-1",
            trigger_reason: "课程薄弱概念需要巩固",
            originating_study_block: "block-recall"
          },
          format: :json

    session = response.parsed_body.fetch("learning_session")
    expect(session).to include(
      "source_type" => "course_weak_concept",
      "source_id" => "concept-1",
      "course_id" => "demo-course-mechanics",
      "concept_id" => "concept-1",
      "trigger_reason" => "课程薄弱概念需要巩固",
      "originating_study_block" => "block-recall"
    )
  end

  it "replans a Study Block after a deterministic user operation" do
    post :reset, format: :json
    before = response.parsed_body.fetch("study_blocks").to_h { |block| [block.fetch("id"), block.fetch("starts_at")] }

    patch :action, params: { event: "complete_block", block_id: "block-recall" }, format: :json
    after = response.parsed_body

    expect(after.fetch("study_blocks").find { |block| block["id"] == "block-recall" }).to include("status" => "completed")
    expect(after.fetch("study_blocks").find { |block| block["id"] == "block-repair" }).to include("starts_at" => be_present)
    expect(after.fetch("study_blocks").find { |block| block["id"] == "block-repair" }.fetch("starts_at")).not_to eq(before.fetch("block-repair"))
    expect(after.fetch("next_action")).to be_present
  end

  it "creates the next persisted Study Block and exposes it to every context after a session" do
    expect(Memury::Ai::TeachingDiagnosisService).not_to receive(:call)

    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")

    patch :action, params: { event: "start_study_block", assignment_id: target_id, source_type: "next_best_action" }, format: :json
    patch :action, params: { event: "answer_recall", correct: false }, format: :json
    patch :action, params: { event: "answer_verification" }, format: :json
    patch :action, params: { event: "start_transfer" }, format: :json
    patch :action, params: { event: "answer_transfer", correct: true }, format: :json

    completed = response.parsed_body
    next_block = completed.fetch("study_blocks").find { |block| block["source_type"] == "replan" }
    expect(next_block).to include(
      "status" => "planned",
      "source_id" => be_present,
      "trigger_reason" => include("重排")
    )
    expect(completed.dig("learning_session", "completed_at")).to be_present
    expect(completed.dig("learner_state", "recent_evidence")).to be_present

    get :state, params: { context_type: "dashboard" }, format: :json
    dashboard_state = response.parsed_body
    get :state, params: { context_type: "course", course_id: next_block.fetch("course_id") }, format: :json
    course_state = response.parsed_body

    expect(course_state.dig("concept", "mastery")).to eq(dashboard_state.dig("concept", "mastery"))
    expect(course_state.dig("next_action", "assignment_id")).to eq(dashboard_state.dig("next_action", "assignment_id"))
    expect(course_state.fetch("study_blocks")).to include(include("id" => next_block.fetch("id"), "status" => "planned"))
    expect(course_state.dig("learner_state", "recent_evidence")).to include(include("title" => "Transfer 迁移题答对"))
    expect(recursive_key_paths(course_state, "reference_answer")).to be_empty
    expect(recursive_key_paths(course_state, "provider_prompt")).to be_empty
    expect(recursive_key_paths(course_state, "provider_response")).to be_empty
    expect(recursive_key_paths(course_state, "authorization")).to be_empty
  end
end
