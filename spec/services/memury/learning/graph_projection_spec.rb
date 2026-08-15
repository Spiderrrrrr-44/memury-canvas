# frozen_string_literal: true

require "spec_helper"

describe Memury::Learning::GraphProjection do
  before do
    skip "learning trace tables are not available" unless Memury::Learning::TraceRecorder.available?
    @user = user_factory
    @other_user = user_factory
  end

  def create_session(user:, assignment_ref: "assignment-42", key:, started_at: Time.zone.parse("2026-08-15 09:00"))
    Memury::Session.create!(
      user:,
      assignment_ref:,
      objective: "功—能定理",
      status: "active",
      idempotency_key: key,
      started_at:,
      metadata: { "concept_id" => "work-energy" }
    )
  end

  it "projects only the current user's Session, Step, Evidence, and parent links" do
    own = create_session(user: @user, key: "own-projection-session")
    foreign = create_session(user: @other_user, key: "foreign-projection-session")
    foreign.steps.create!(kind: "answer", sequence: 1, status: "completed", idempotency_key: "foreign-step", started_at: Time.zone.now)
    recall = own.steps.create!(
      kind: "answer", sequence: 1, status: "completed", idempotency_key: "answer-step",
      started_at: Time.zone.parse("2026-08-15 09:05"),
      input: { "student_answer" => "PRIVATE RAW ANSWER MUST NOT LEAVE THE SERVER" },
      output: { "provider_raw_body" => "PRIVATE PROVIDER BODY" }
    )
    own.evidences.create!(
      step: recall,
      kind: "diagnosis", fingerprint: "diagnosis-one", source: "rule_fallback", verified: true,
      observed_at: Time.zone.parse("2026-08-15 09:06"),
      payload: { "diagnosis_summary" => "符号方向仍需确认", "misconception_type" => "conceptual" }
    )
    branch = own.steps.create!(
      kind: "student_question", sequence: 2, status: "completed", idempotency_key: "branch-step",
      started_at: Time.zone.parse("2026-08-15 09:07"),
      input: { "question" => "为什么支持力不做功？", "parent_step_id" => recall.id, "branch_kind" => "continuation" }, output: {}
    )
    own.evidences.create!(
      step: branch,
      kind: "student_question", fingerprint: "branch-question", source: "student", verified: false,
      observed_at: Time.zone.parse("2026-08-15 09:07"), payload: { "question" => "为什么支持力不做功？" }
    )

    graph = described_class.call(user: @user, assignment_ref: "assignment-42")

    expect(graph.fetch("learning_session_id")).to eq(own.id.to_s)
    expect(graph.fetch("nodes").pluck("title")).to include("功—能定理", "为什么支持力不做功？", "概念边界待确认")
    expect(graph.fetch("nodes").to_json).not_to include("foreign-step")
    expect(graph.fetch("edges")).to include(
      hash_including(
        "source_node_id" => "step-#{recall.id}",
        "target_node_id" => "step-#{branch.id}",
        "relation" => "branch"
      )
    )
    diagnosis = graph.fetch("nodes").find { |node| node["kind"] == "diagnosis" }
    expect(diagnosis.fetch("verification_state")).to eq("unresolved")
    expect(graph.to_json).not_to include("PRIVATE RAW ANSWER")
    expect(graph.to_json).not_to include("PRIVATE PROVIDER BODY")
    expect(diagnosis.dig("evidence_refs", 0, "verified")).to be(false)
  end

  it "marks only trusted transfer validation as verified" do
    session = create_session(user: @user, key: "trusted-transfer-session")
    step = session.steps.create!(
      kind: "transfer_assessment", sequence: 1, status: "completed", idempotency_key: "transfer-step",
      started_at: Time.zone.now, input: {}, output: {}
    )
    session.evidences.create!(
      step:,
      kind: "transfer_validation", fingerprint: "trusted-transfer", source: "deterministic_validator",
      verified: true, observed_at: Time.zone.now,
      payload: { "validation_basis" => "deterministic_rule", "summary" => "迁移验证通过" }
    )

    graph = described_class.call(user: @user, assignment_ref: "assignment-42")
    node = graph.fetch("nodes").find { |item| item["kind"] == "verification_result" }

    expect(node.fetch("verification_state")).to eq("verified")
    expect(graph.fetch("verified_evidence_id")).to be_present
    expect(node.fetch("created_at")).to eq(step.started_at.iso8601)
  end

  it "serializes zoned timestamps as ISO 8601" do
    Time.use_zone("Asia/Shanghai") do
      session = create_session(
        user: @user,
        key: "timezone-session",
        started_at: Time.zone.parse("2026-08-15 09:00")
      )
      session.steps.create!(
        kind: "recall", sequence: 1, status: "completed", idempotency_key: "timezone-step",
        started_at: Time.zone.parse("2026-08-15 09:05"), input: {}, output: {}
      )

      graph = described_class.call(user: @user, assignment_ref: "assignment-42")
      expect(graph.fetch("created_at")).to eq("2026-08-15T09:00:00+08:00")
      expect(graph.fetch("nodes").last.fetch("created_at")).to eq("2026-08-15T09:05:00+08:00")
    end
  end

  it "falls back to the prior projected step for an invalid historical parent" do
    session = create_session(user: @user, key: "invalid-parent-session")
    first = session.steps.create!(
      kind: "answer", sequence: 1, status: "completed", idempotency_key: "valid-first-step",
      started_at: Time.zone.now, input: {}, output: {}
    )
    second = session.steps.create!(
      kind: "validation", sequence: 2, status: "completed", idempotency_key: "invalid-parent-step",
      started_at: Time.zone.now, input: { "parent_step_id" => 999_999 }, output: {}
    )

    graph = described_class.call(user: @user, assignment_ref: "assignment-42")
    edge = graph.fetch("edges").find { |item| item["target_node_id"] == "step-#{second.id}" }

    expect(edge).to include(
      "source_node_id" => "step-#{first.id}",
      "relation" => "sequence"
    )
    expect(graph.fetch("edges").pluck("source_node_id")).not_to include("step-999999")
  end

  it "returns a valid empty graph instead of demo nodes" do
    graph = described_class.call(user: @user, assignment_ref: "missing-assignment")

    expect(graph).to include(
      "learning_session_id" => nil,
      "assignment_id" => "missing-assignment",
      "current_node_id" => nil,
      "nodes" => [],
      "edges" => [],
      "writable" => false
    )
  end
end
