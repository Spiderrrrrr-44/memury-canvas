# frozen_string_literal: true

require "spec_helper"

describe Memury::Learning::GraphCommandService do
  before do
    skip "learning trace tables are not available" unless Memury::Learning::TraceRecorder.available?
    @user = user_factory
    @session = Memury::Session.create!(
      user: @user, assignment_ref: "assignment-42", objective: "功—能定理", status: "active",
      idempotency_key: "graph-command-session", started_at: Time.zone.now
    )
    @parent = @session.steps.create!(
      kind: "answer", sequence: 1, status: "completed", idempotency_key: "parent-step",
      started_at: Time.zone.now, input: {}, output: {}
    )
  end

  it "persists a real parent Step and unverified Evidence idempotently" do
    attributes = {
      user: @user,
      assignment_ref: "assignment-42",
      parent_node_id: "step-#{@parent.id}",
      question: "为什么支持力不做功？",
      request_id: "request-branch-001"
    }

    2.times { described_class.continue!(**attributes) }

    branch = @session.steps.find_by!(kind: "student_question")
    expect(branch.input).to include(
      "parent_step_id" => @parent.id,
      "parent_node_id" => "step-#{@parent.id}",
      "branch_kind" => "continuation"
    )
    expect(@session.steps.where(kind: "student_question").count).to eq(1)
    expect(branch.evidences.count).to eq(1)
    expect(branch.evidences.first).not_to be_verified
    response = @session.steps.find_by!(kind: "tutor_response")
    expect(response.output.fetch("answer")).to be_present
    expect(@session.reload.summary).to be_present
    expect(@session.metadata["current_learning_graph_node_id"]).to eq("step-#{response.id}")
  end

  it "starts a document conversation when no prior learning Session exists" do
    @session.destroy!

    response = described_class.continue!(
      user: @user,
      assignment_ref: "new-document-7",
      parent_node_id: "document-root",
      question: "这段话的核心条件是什么？",
      request_id: "request-document-001",
      document_title: "Lecture note 7",
      document_excerpt: "A force does work only through displacement.",
      locale: "zh-CN"
    )

    expect(response.kind).to eq("tutor_response")
    expect(response.session.objective).to eq("Lecture note 7")
    expect(response.session.steps.pluck(:kind)).to eq(%w[student_question tutor_response])
    expect(response.session.summary).to be_present
  end

  it "rejects a parent from another Session" do
    foreign_session = Memury::Session.create!(
      user: @user, assignment_ref: "assignment-99", objective: "foreign", status: "active",
      idempotency_key: "foreign-session", started_at: Time.zone.now
    )
    foreign_step = foreign_session.steps.create!(
      kind: "answer", sequence: 1, status: "completed", idempotency_key: "foreign-parent",
      started_at: Time.zone.now, input: {}, output: {}
    )

    expect do
      described_class.continue!(
        user: @user, assignment_ref: "assignment-42", parent_node_id: "step-#{foreign_step.id}",
        question: "非法分支", request_id: "request-branch-002"
      )
    end.to raise_error(described_class::InvalidCommand, "parent_node_invalid")
    expect(@session.steps.where(kind: "student_question")).to be_empty
  end

  it "rejects an unknown parent in the same Session" do
    expect do
      described_class.continue!(
        user: @user, assignment_ref: "assignment-42", parent_node_id: "step-999999",
        question: "无效父节点", request_id: "request-branch-003"
      )
    end.to raise_error(described_class::InvalidCommand, "parent_node_invalid")
  end

  it "persists current-node selection only for a node in the projected graph" do
    described_class.select!(
      user: @user,
      assignment_ref: "assignment-42",
      node_id: "step-#{@parent.id}"
    )
    expect(@session.reload.metadata["current_learning_graph_node_id"]).to eq("step-#{@parent.id}")

    expect do
      described_class.select!(user: @user, assignment_ref: "assignment-42", node_id: "step-999999")
    end.to raise_error(described_class::InvalidCommand, "node_not_found")
  end
end
