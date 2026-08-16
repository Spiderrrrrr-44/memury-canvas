# frozen_string_literal: true

require "spec_helper"

describe MemuryController do
  before do
    skip "learning trace tables are not available" unless Memury::Learning::TraceRecorder.available?
    Account.default.enable_feature!(:memury)
    @user = user_factory
    user_session(@user)
  end

  def create_session(user:, assignment_ref:, key:)
    session = Memury::Session.create!(
      user:, assignment_ref:, objective: "功—能定理", status: "active",
      idempotency_key: key, started_at: Time.zone.now
    )
    session.steps.create!(
      kind: "answer", sequence: 1, status: "completed", idempotency_key: "#{key}-step",
      started_at: Time.zone.now, input: {}, output: {}
    )
    session
  end

  it "returns only the signed-in user's graph" do
    own = create_session(user: @user, assignment_ref: "assignment-42", key: "own-graph")
    other = user_factory
    foreign = create_session(user: other, assignment_ref: "assignment-42", key: "foreign-graph")

    get :learning_graph, params: { assignment_id: "assignment-42" }, format: :json

    expect(response).to be_successful
    expect(response.parsed_body.fetch("learning_session_id")).to eq(own.id.to_s)
    expect(response.body).not_to include("session-#{foreign.id}")
  end

  it "creates a persistent branch and returns the updated graph" do
    session = create_session(user: @user, assignment_ref: "assignment-42", key: "branch-graph")
    parent = session.steps.first

    post :continue_learning_graph, params: {
      assignment_id: "assignment-42",
      parent_node_id: "step-#{parent.id}",
      question: "为什么支持力不做功？",
      request_id: "controller-request-001"
    }, format: :json

    expect(response).to be_successful
    expect(response.parsed_body.fetch("edges")).to include(
      hash_including("source_node_id" => "step-#{parent.id}", "relation" => "branch")
    )
    expect(session.reload.steps.where(kind: "student_question").count).to eq(1)
    expect(session.steps.where(kind: "tutor_response").count).to eq(1)
    expect(response.parsed_body.fetch("conversation_summary")).to be_present
  end
end
