# frozen_string_literal: true

require "spec_helper"

describe Memury::Learning::AcademicEvidenceProjector do
  before do
    skip "semester evidence table is not available" unless Memury::AcademicEvidence.table_exists?
    @user = user_factory
    @session = Memury::Session.create!(
      user: @user, assignment_ref: "assignment-42", objective: "功—能定理", status: "completed",
      idempotency_key: "academic-projector-session", started_at: Time.zone.now,
      metadata: { "concept_id" => "work-energy" }
    )
    @step = @session.steps.create!(
      kind: "transfer_assessment", sequence: 1, status: "completed", idempotency_key: "transfer-step",
      started_at: Time.zone.now, input: {}, output: {}
    )
  end

  def evidence(verified:, basis:, fingerprint:)
    @session.evidences.create!(
      step: @step,
      kind: "transfer_validation", fingerprint:, source: "deterministic_validator",
      verified:, confidence: 0.91, observed_at: Time.zone.now,
      payload: { "validation_basis" => basis, "summary" => "迁移验证完成" }
    )
  end

  it "does not promote unverified or untrusted graph evidence" do
    unverified = evidence(verified: false, basis: "deterministic_rule", fingerprint: "unverified")
    legacy = evidence(verified: true, basis: "legacy_demo_signal", fingerprint: "legacy")

    expect(described_class.call(user: @user, session: @session, evidence: unverified)).to be_nil
    expect(described_class.call(user: @user, session: @session, evidence: legacy)).to be_nil
    expect(Memury::AcademicEvidence.where(user: @user, source_kind: "memury_learning_session")).to be_empty
  end

  it "promotes trusted transfer Evidence exactly once" do
    trusted = evidence(verified: true, basis: "deterministic_rule", fingerprint: "trusted")

    2.times { described_class.call(user: @user, session: @session, evidence: trusted) }

    records = Memury::AcademicEvidence.where(user: @user, source_kind: "memury_learning_session")
    expect(records.count).to eq(1)
    expect(records.first).to have_attributes(
      verified: true,
      kind: "quiz_item",
      concept: "work-energy"
    )
    expect(records.first.metadata).to include(
      "learning_session_id" => @session.id,
      "learning_evidence_id" => trusted.id,
      "validation_basis" => "deterministic_rule"
    )
  end
end
