# frozen_string_literal: true

require "spec_helper"

describe MemuryController do
  before do
    Account.default.enable_feature!(:memury)
    @user = user_factory
    user_session(@user)
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
end
