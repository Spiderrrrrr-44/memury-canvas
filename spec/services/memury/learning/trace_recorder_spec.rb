# frozen_string_literal: true

require "spec_helper"

describe Memury::Learning::TraceRecorder do
  before do
    skip "learning trace tables are not available in this test database" unless described_class.available?
    @user = user_factory
  end

  def state_for(event = "start_study_block")
    state = Memury::DemoState.build.deep_stringify_keys
    state["learning_session"]["target_assignment_id"] = "mech-force"
    state["learning_session"]["started_at"] = Time.zone.now.iso8601
    state["learning_session"]["source_type"] = "next_best_action"
    state["phase"] = event == "answer_transfer" ? "complete" : "recall"
    state
  end

  it "persists a Session, Step, and verified/failed Evidence without duplicates" do
    state = state_for
    described_class.record_event!(
      user: @user,
      state:,
      event: "start_study_block",
      params: { "event" => "start_study_block", "assignment_id" => "mech-force" },
      before_state: state.deep_dup
    )
    session = Memury::Session.find_by!(user: @user)
    expect(session.objective).to include("平衡力")
    expect(session.steps.count).to eq(1)
    expect(session.evidences.count).to eq(1)
    expect(session.evidences.first.verified).to be(true)

    answer_state = state.deep_dup
    answer_state["diagnostic"] = {
      "diagnosis_summary" => "观察到概念混淆",
      "answer_judgment" => "incorrect",
      "misconception_type" => "conceptual",
      "evidence" => ["学生答案线索"],
      "confidence" => 0.7,
      "source" => "rule_fallback"
    }
    answer_state["phase"] = "verify"
    params = { "event" => "answer_recall", "student_answer" => "我把两个物体混在一起了" }
    2.times do
      described_class.record_event!(user: @user, state: answer_state, event: "answer_recall", params:, before_state: state)
    end

    expect(session.reload.steps.count).to eq(2)
    expect(session.reload.evidences.where(kind: "student_answer").count).to eq(1)
    expect(session.reload.evidences.where(kind: "diagnosis").count).to eq(1)
  end

  it "records failed validation but does not mark it as verified evidence" do
    state = state_for("answer_transfer")
    state["learning_session"]["transfer_validation"] = {
      "status" => "failed",
      "verified" => false,
      "confidence" => 0.6,
      "reason_code" => "transfer_answer_incomplete",
      "summary" => "关键判断缺失",
      "source" => "deterministic_validator"
    }
    state["learning_session"]["transfer_correct"] = false

    described_class.record_event!(
      user: @user,
      state:,
      event: "answer_transfer",
      params: { "event" => "answer_transfer", "correct" => false },
      before_state: state.deep_dup
    )

    evidence = Memury::Evidence.find_by!(kind: "transfer_validation")
    expect(evidence.verified).to be(false)
    expect(evidence.source).to eq("deterministic_validator")
  end
end
