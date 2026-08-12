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

  def prepare_transfer
    post :reset, format: :json
    target_id = response.parsed_body.fetch("next_action").fetch("assignment_id")
    patch :action, params: { event: "start_study_block", assignment_id: target_id }, format: :json
    patch :action, params: { event: "answer_recall", student_answer: "我混淆了两个受力物体" }, format: :json
    patch :action, params: { event: "answer_verification" }, format: :json
    patch :action, params: { event: "start_transfer" }, format: :json
    target_id
  end

  def answer_transfer(target_id)
    patch :action, params: {
      event: "answer_transfer",
      assignment_id: target_id,
      student_answer: "桌面对书的支持力与书对桌面的压力作用在不同物体上，不是一对平衡力。"
    }, format: :json
  end

  class TransactionRecordingProvider
    attr_reader :transaction_depths

    def initialize(delegate)
      @delegate = delegate
      @transaction_depths = []
    end

    def method_missing(name, *args, **kwargs, &block)
      @transaction_depths << [name, ActiveRecord::Base.connection.open_transactions]
      @delegate.public_send(name, *args, **kwargs, &block)
    end

    def respond_to_missing?(name, include_private = false)
      @delegate.respond_to?(name, include_private) || super
    end
  end

  it "runs provider work before opening the persistence transaction" do
    baseline = ActiveRecord::Base.connection.open_transactions
    provider = TransactionRecordingProvider.new(Memury::Teaching::DeterministicProvider.new)
    allow(Memury::Teaching::ProviderRegistry).to receive(:current).and_return(provider)

    prepare_transfer

    expect(provider.transaction_depths).not_to be_empty
    # Canvas controller specs already wrap each request in one fixture
    # transaction. Provider work may run inside that request boundary, but
    # must not add the LearnerProfile.with_lock transaction on top of it.
    expect(provider.transaction_depths.map(&:last)).to all(eq(baseline + 1))
  end

  it "rolls back Session, Step, Evidence, profile, and planner state when Evidence persistence fails" do
    target_id = prepare_transfer
    profile = Memury::LearnerProfile.find_by!(user: @user)
    before_state = profile.state.deep_dup
    counts = [Memury::Session.count, Memury::Step.count, Memury::Evidence.count]
    allow_any_instance_of(Memury::Evidence).to receive(:save!).and_raise(
      ActiveRecord::StatementInvalid.new("evidence write failed")
    )

    answer_transfer(target_id)

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch("error")).to eq("trace_storage_unavailable")
    expect(profile.reload.state).to eq(before_state)
    expect([Memury::Session.count, Memury::Step.count, Memury::Evidence.count]).to eq(counts)
  end

  it "rolls back all trace and learning changes when LearnerProfile persistence fails" do
    target_id = prepare_transfer
    profile = Memury::LearnerProfile.find_by!(user: @user)
    before_state = profile.state.deep_dup
    counts = [Memury::Session.count, Memury::Step.count, Memury::Evidence.count]
    allow_any_instance_of(Memury::LearnerProfile).to receive(:update!).and_raise(
      ActiveRecord::StatementInvalid.new("profile write failed")
    )

    answer_transfer(target_id)

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch("error")).to eq("trace_storage_unavailable")
    expect(profile.reload.state).to eq(before_state)
    expect([Memury::Session.count, Memury::Step.count, Memury::Evidence.count]).to eq(counts)
  end

  it "does not expose a successful completion when the decision log write fails" do
    target_id = prepare_transfer
    profile = Memury::LearnerProfile.find_by!(user: @user)
    before_state = profile.state.deep_dup
    counts = [Memury::Session.count, Memury::Step.count, Memury::Evidence.count]
    allow_any_instance_of(Memury::LearnerProfile).to receive(:update!).and_raise(
      ActiveRecord::RecordInvalid.new(profile)
    )

    answer_transfer(target_id)

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch("error")).to eq("trace_storage_unavailable")
    expect(profile.reload.state).to eq(before_state)
    expect([Memury::Session.count, Memury::Step.count, Memury::Evidence.count]).to eq(counts)
  end

  it "rolls back when binding the decision evidence fails" do
    target_id = prepare_transfer
    profile = Memury::LearnerProfile.find_by!(user: @user)
    before_state = profile.state.deep_dup
    counts = [Memury::Session.count, Memury::Step.count, Memury::Evidence.count]
    allow_any_instance_of(Memury::Step).to receive(:save!).and_raise(
      ActiveRecord::StatementInvalid.new("decision binding failed")
    )

    answer_transfer(target_id)

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch("error")).to eq("trace_storage_unavailable")
    expect(profile.reload.state).to eq(before_state)
    expect([Memury::Session.count, Memury::Step.count, Memury::Evidence.count]).to eq(counts)
  end
end
