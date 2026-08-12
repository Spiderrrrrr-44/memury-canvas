# frozen_string_literal: true

require "spec_helper"

describe MemuryController do
  before do
    skip "learning trace tables are not available in this test database" unless Memury::Learning::TraceRecorder.available?
    Account.default.enable_feature!(:memury)
    @user = user_factory
    user_session(@user)
    allow(Memury::Teaching::ProviderRegistry).to receive(:current).and_return(Memury::Teaching::DeterministicProvider.new)
  end

  it "runs the UI event contract through a traced independently validated transfer" do
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")

    patch :action, params: { event: "start_study_block", assignment_id: target_id }, format: :json
    patch :action, params: { event: "answer_recall", student_answer: "我把不同物体上的力混在一起了" }, format: :json
    patch :action, params: { event: "answer_verification" }, format: :json
    patch :action, params: { event: "start_transfer" }, format: :json
    transfer = response.parsed_body.fetch("learning_session")
    expect(transfer).not_to have_key("practice_candidate")
    expect(transfer).to include("target_assignment_id" => target_id.to_s)

    patch :action, params: {
      event: "answer_transfer",
      correct: true,
      student_answer: "桌面对书的支持力与书对桌面的压力作用在不同物体上，不是一对平衡力。"
    }, format: :json
    completed = response.parsed_body
    expect(completed.fetch("phase")).to eq("complete")
    expect(completed.dig("learning_session", "transfer_validation", "verified")).to be(true)
    expect(completed.dig("learning_session", "evidence_summary", "verified_count")).to eq(2)
    expect(completed.fetch("completed_assignment_ids").map(&:to_s)).to include(target_id.to_s)
    expect(completed.fetch("decision_logs").last).to include(
      "before" => include("mastery"),
      "after" => include("mastery"),
      "trigger_evidence" => "transfer_validation"
    )

    session = Memury::Session.find_by!(user: @user)
    verified_evidence = session.evidences.find_by!(kind: "transfer_validation", verified: true)
    expect(completed.fetch("decision_logs").last.fetch("trigger_evidence_id")).to eq(verified_evidence.id)
    expect(session.status).to eq("completed")
    expect(session.steps.pluck(:kind)).to include("recall", "answer", "validation", "practice_generation", "transfer_assessment")
    expect(session.evidences.where(verified: true).count).to be > 0
  end

  it "does not mark an assignment complete when the independent transfer validator fails" do
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")
    initial_mastery = initial.fetch("concept").fetch("mastery")

    patch :action, params: { event: "start_study_block", assignment_id: target_id }, format: :json
    patch :action, params: { event: "answer_recall", correct: false }, format: :json
    patch :action, params: { event: "answer_verification" }, format: :json
    patch :action, params: { event: "start_transfer" }, format: :json
    patch :action, params: { event: "answer_transfer", correct: false }, format: :json

    failed = response.parsed_body
    expect(failed.dig("learning_session", "transfer_validation", "verified")).to be(false)
    expect(failed.fetch("completed_assignment_ids").map(&:to_s)).not_to include(target_id.to_s)
    expect(failed.fetch("concept").fetch("mastery")).to eq(initial_mastery)
    expect(failed.fetch("decision_logs").last.fetch("reason_code")).to eq("legacy_demo_answer_failed")
  end

  it "records legacy correct without treating it as verified learning evidence" do
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")
    initial_mastery = initial.fetch("concept").fetch("mastery")

    patch :action, params: { event: "start_study_block", assignment_id: target_id }, format: :json
    patch :action, params: { event: "answer_recall", correct: true }, format: :json
    patch :action, params: { event: "start_transfer" }, format: :json
    patch :action, params: { event: "answer_transfer", correct: true }, format: :json

    expect(response).to have_http_status(:ok)
    legacy = response.parsed_body
    expect(legacy.fetch("phase")).to eq("transfer")
    expect(legacy.dig("learning_session", "transfer_validation", "verified")).to be(false)
    expect(legacy.dig("learning_session", "transfer_validation", "validation_basis")).to eq("legacy_demo_signal")
    expect(legacy.fetch("concept").fetch("mastery")).to eq(initial_mastery)
    expect(legacy.fetch("completed_assignment_ids").map(&:to_s)).not_to include(target_id.to_s)

    evidence = Memury::Evidence.find_by!(kind: "legacy_demo_signal")
    expect(evidence.verified).to be(false)
    expect(legacy.fetch("decision_logs").last.fetch("trigger_evidence_id")).to eq(
      Memury::Evidence.find_by!(kind: "transfer_validation").id
    )
  end
end
