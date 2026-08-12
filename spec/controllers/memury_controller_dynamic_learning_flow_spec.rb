# frozen_string_literal: true

require "spec_helper"

describe MemuryController do
  before do
    skip "learning trace tables are not available in this test database" unless Memury::Learning::TraceRecorder.available?
    Account.default.enable_feature!(:memury)
    @user = user_factory
    user_session(@user)
  end

  let(:recording_provider_class) do
    Class.new do
      attr_reader :calls

      def initialize(validate: true, transfer: true)
        @validate = validate
        @transfer = transfer
        @calls = []
      end

      def diagnose(context)
        @calls << [:diagnose, context.to_h]
        Memury::Teaching::Diagnosis.new(
          diagnosis_summary: "学生把不同受力物体混在了一起。",
          answer_judgment: "incorrect",
          misconception_type: "conceptual",
          evidence: ["回答提到了方向，但没有区分受力对象。"],
          confidence: 0.82,
          verification_question: "两个力分别作用在哪个物体上？",
          hint: "先标出每个力的受力物体。",
          transfer_question: "换一个接触情境，两个相互作用力还作用在同一物体上吗？",
          learner_state_suggestion: { "skill" => "受力对象", "suggested_status" => "review", "reason" => "需要迁移验证" },
          source: "openai",
          metadata: { "provider" => "fake_openai", "capability" => "diagnose" }
        )
      end

      def guide(context)
        @calls << [:guide, context.to_h]
        Memury::Teaching::Guidance.new(
          level: 2,
          layers: ["先圈出两个力各自作用的物体。"],
          contains_direct_answer: false,
          misconception: "conceptual",
          next_step: "用新情境回答迁移题。",
          confidence: 0.78,
          source: "openai",
          metadata: { "provider" => "fake_openai", "capability" => "guide" }
        )
      end

      def generate_practice(context)
        @calls << [:generate_practice, context.to_h]
        Memury::Teaching::PracticeCandidate.new(
          id: "fake-practice-1",
          prompt: "电梯中的人与地面对人的力分别作用在哪个物体上？",
          expected_answer: "作用力与反作用力作用在不同物体上。",
          explanation: "判断力的关系时先检查受力对象。",
          knowledge_point: context.knowledge_point,
          difficulty: "transfer",
          question_type: "scenario",
          source_basis: "trusted course source: mechanics notes",
          source: "openai",
          metadata: { "provider" => "fake_openai", "capability" => "generate_practice" }
        )
      end

      def validate_practice(context)
        @calls << [:validate_practice, context.to_h]
        return failed_validation unless @validate

        Memury::Teaching::ValidationResult.new(
          status: "passed",
          verified: true,
          confidence: 0.91,
          reason_code: "candidate_validated",
          summary: "题目与课程依据自洽并适合迁移。",
          source: "openai",
          validation_basis: "trusted_course_source",
          knowledge_point_match: true,
          difficulty_fit: true,
          self_consistent: true,
          answer_correct: true,
          explanation_consistent: true,
          answer_leak: false,
          transfer_suitable: true,
          metadata: { "provider" => "fake_openai", "capability" => "validate_practice" }
        )
      end

      def assess_transfer(context)
        @calls << [:assess_transfer, context.to_h]
        if context.student_answer.to_s.strip.blank? && !context.legacy_correct.nil?
          return Memury::Teaching::ValidationResult.new(
            status: "failed",
            verified: false,
            confidence: 0.0,
            reason_code: "legacy_demo_signal",
            summary: "只收到旧版 correct 信号，没有可验证的学生答案。",
            source: "legacy_ui",
            validation_basis: "legacy_demo_signal",
            metadata: { "provider" => "fake_openai", "capability" => "assess_transfer" }
          )
        end

        unless @transfer
          return Memury::Teaching::ValidationResult.new(
            status: "failed",
            verified: false,
            confidence: 0.84,
            reason_code: "transfer_answer_incomplete",
            summary: "答案缺少受力对象判断。",
            source: "openai",
            validation_basis: "trusted_course_source",
            independent_completed: true,
            hint_dependent: context.hint_dependent,
            scoring_basis: context.candidate_expected_answer,
            mastery_delta_suggestion: -0.04,
            metadata: { "provider" => "fake_openai", "capability" => "assess_transfer" }
          )
        end

        Memury::Teaching::ValidationResult.new(
          status: "passed",
          verified: true,
          confidence: 0.94,
          reason_code: "transfer_answer_validated",
          summary: "答案独立覆盖关键判断。",
          source: "openai",
          validation_basis: "trusted_course_source",
          independent_completed: true,
          hint_dependent: context.hint_dependent,
          scoring_basis: context.candidate_expected_answer,
          mastery_delta_suggestion: 0.2,
          metadata: { "provider" => "fake_openai", "capability" => "assess_transfer" }
        )
      end

      def summarize_evidence(context)
        @calls << [:summarize_evidence, context.to_h]
        Memury::Teaching::EvidenceSummary.new(
          summary: "已验证的迁移证据可供 Planner 使用。",
          verified_count: context.evidence.count { |item| item["verified"] == true },
          total_count: context.evidence.length,
          confidence: 0.9,
          source: "openai",
          verified_conclusions: ["迁移题独立通过"],
          unresolved_misconceptions: [],
          hint_dependence: "none",
          transfer_result: "passed",
          evidence_strength: "strong",
          planner_summary: "迁移题独立通过，可降低当前概念风险。",
          metadata: { "provider" => "fake_openai", "capability" => "summarize_evidence" }
        )
      end

      private

      def failed_validation
        Memury::Teaching::ValidationResult.new(
          status: "failed",
          verified: false,
          confidence: 0.0,
          reason_code: "validator_rejected",
          summary: "可信依据不足，拒绝候选题。",
          source: "openai",
          validation_basis: "insufficient_basis",
          metadata: { "provider" => "fake_openai", "capability" => "validate_practice" }
        )
      end
    end
  end

  def use_provider(provider)
    allow(Memury::Teaching::ProviderRegistry).to receive(:current).and_return(provider)
  end

  def start_transfer_flow(target_id, recall_answer: "学生混淆了两个受力物体。")
    patch :action, params: { event: "start_study_block", assignment_id: target_id }, format: :json
    patch :action, params: { event: "answer_recall", student_answer: recall_answer }, format: :json
    patch :action, params: { event: "answer_verification" }, format: :json
    patch :action, params: { event: "start_transfer" }, format: :json
  end

  around do |example|
    if example.metadata[:deterministic_demo_clock]
      Timecop.freeze(Time.zone.parse("2026-08-10 10:00:00 UTC")) { example.run }
    else
      example.run
    end
  end

  it "proves the dynamic provider-neutral teaching loop with concrete planner changes", :deterministic_demo_clock do
    provider = recording_provider_class.new
    use_provider(provider)
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")
    mastery_before = initial.fetch("concept").fetch("mastery")
    risk_before = initial.fetch("risks").find { |risk| risk["id"].to_s == target_id.to_s }.fetch("risk")
    plan_before = initial.fetch("study_blocks").map { |block| block.fetch("id") }
    scores_before = initial.fetch("assignments").to_h { |assignment| [assignment.fetch("id"), assignment["score"]] }

    expect(target_id).to eq("mech-force")
    expect(mastery_before).to eq(0.42)
    expect(risk_before).to eq(0.85)
    expect(plan_before).to eq(%w[block-recall block-repair block-transfer])

    start_transfer_flow(target_id)
    patch(
      :action,
      params: {
        event: "answer_transfer",
        student_answer: "作用力与反作用力作用在不同物体上。"
      },
      format: :json
    )

    expect(response).to have_http_status(:ok)
    completed = response.parsed_body
    mastery_after = completed.fetch("concept").fetch("mastery")
    risk_after = completed.fetch("risks").find { |risk| risk["id"].to_s == target_id.to_s }.fetch("risk")
    plan_after = completed.fetch("study_blocks").map { |block| block.fetch("id") }

    expect(mastery_after).to eq(0.65)
    expect(risk_after).to eq(0.27)
    expect(plan_after).to eq(
      %w[
        block-recall
        block-repair
        block-transfer
        block-mech-quiz-recall
        block-mech-quiz-repair
        block-mech-quiz-transfer
      ]
    )
    expect(completed.fetch("next_action").fetch("assignment_id")).to eq("mech-quiz")

    expect(
      completed.fetch("study_blocks").map { |block| block.slice("id", "stage", "status") }
    ).to eq(
      [
        { "id" => "block-recall", "stage" => "recall", "status" => "completed" },
        { "id" => "block-repair", "stage" => "repair", "status" => "completed" },
        { "id" => "block-transfer", "stage" => "transfer", "status" => "completed" },
        { "id" => "block-mech-quiz-recall", "stage" => "recall", "status" => "planned" },
        { "id" => "block-mech-quiz-repair", "stage" => "repair", "status" => "planned" },
        { "id" => "block-mech-quiz-transfer", "stage" => "transfer", "status" => "planned" }
      ]
    )
    expect(completed.fetch("learning_session").fetch("transfer_validation").fetch("verified")).to be(true)
    expect(completed.fetch("assignments").to_h { |assignment| [assignment.fetch("id"), assignment["score"]] }).to eq(scores_before)

    log = completed.fetch("decision_logs").last
    evidence = Memury::Evidence.find_by!(kind: "transfer_validation", verified: true)
    expect(log.fetch("trigger_evidence_id")).to eq(evidence.id)
    expect(log.fetch("risk_before")).to eq(risk_before)
    expect(log.fetch("risk_after")).to eq(risk_after)
    expect(log.fetch("plan_before").fetch("study_blocks").map { |block| block.fetch("id") }).to eq(plan_before)
    expect(log.fetch("plan_after").fetch("study_blocks").map { |block| block.fetch("id") }).to eq(plan_after)

    session = Memury::Session.find_by!(user: @user)
    step = session.steps.find_by!(kind: "transfer_assessment")
    expect(step.status).to eq("completed")
    expect(evidence.learning_session_id).to eq(session.id)
    expect(evidence.learning_step_id).to eq(step.id)
    expect(provider.calls.map(&:first)).to include(
      :diagnose, :guide, :generate_practice, :validate_practice, :assess_transfer, :summarize_evidence
    )
    expect(provider.calls.find { |name, _| name == :assess_transfer }.last).not_to have_key("legacy_correct")

    calls_before_retry = provider.calls.length
    evidence_count_before_retry = Memury::Evidence.count
    patch(
      :action,
      params: {
        event: "answer_transfer",
        student_answer: "作用力与反作用力作用在不同物体上。"
      },
      format: :json
    )

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("concept").fetch("mastery")).to eq(mastery_after)
    expect(Memury::Evidence.count).to eq(evidence_count_before_retry)
    expect(provider.calls.length).to eq(calls_before_retry)
  end

  it "does not write Canvas grades or replan submitted work", :deterministic_demo_clock do
    provider = recording_provider_class.new
    use_provider(provider)
    pending_state = Memury::DemoState.build
    pending_assignment = pending_state.fetch(:assignments).find { |assignment| assignment.fetch(:id) == "mech-quiz" }
    pending_assignment[:submitted] = true
    pending_assignment[:score] = nil
    allow(Memury::DemoState).to receive(:build) { pending_state.deep_dup }

    expect_any_instance_of(Assignment).not_to receive(:grade_student)
    expect_any_instance_of(Submission).not_to receive(:update!)

    post :reset, format: :json
    target_id = response.parsed_body.fetch("next_action").fetch("assignment_id")
    expect(target_id).to eq("mech-force")

    start_transfer_flow(target_id)
    patch(
      :action,
      params: {
        event: "answer_transfer",
        student_answer: "作用力与反作用力作用在不同物体上。"
      },
      format: :json
    )

    expect(response).to have_http_status(:ok)
    completed = response.parsed_body
    still_pending = completed.fetch("assignments").find { |assignment| assignment.fetch("id") == "mech-quiz" }
    expect(still_pending).to include("submitted" => true, "score" => nil)
    expect(completed.fetch("completed_assignment_ids")).not_to include("mech-quiz")
    expect(completed.fetch("next_action").fetch("assignment_id")).not_to eq("mech-quiz")
    expect(completed.fetch("study_blocks").filter_map { |block| block["source_id"] }).not_to include("mech-quiz")
  end

  it "keeps mastery, risk, and plan unchanged for a legacy correct signal" do
    provider = recording_provider_class.new
    use_provider(provider)
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")
    initial_mastery = initial.fetch("concept").fetch("mastery")
    initial_risk = initial.fetch("risks").find { |risk| risk["id"].to_s == target_id.to_s }.fetch("risk")
    initial_plan = initial.fetch("study_blocks").map { |block| block.fetch("id") }

    start_transfer_flow(target_id)
    patch :action, params: { event: "answer_transfer", correct: true }, format: :json

    legacy = response.parsed_body
    expect(legacy.fetch("phase")).to eq("transfer")
    expect(legacy.dig("learning_session", "transfer_validation", "verified")).to be(false)
    expect(legacy.dig("learning_session", "transfer_validation", "validation_basis")).to eq("legacy_demo_signal")
    expect(legacy.fetch("concept").fetch("mastery")).to eq(initial_mastery)
    expect(legacy.fetch("risks").find { |risk| risk["id"].to_s == target_id.to_s }.fetch("risk")).to eq(initial_risk)
    expect(legacy.fetch("study_blocks").map { |block| block.fetch("id") }).to eq(initial_plan)
    expect(Memury::Evidence.find_by!(kind: "legacy_demo_signal").verified).to be(false)
  end

  it "does not promote state when the independent candidate validator rejects" do
    provider = recording_provider_class.new(validate: false, transfer: false)
    use_provider(provider)
    post :reset, format: :json
    initial = response.parsed_body
    target_id = initial.fetch("next_action").fetch("assignment_id")
    initial_mastery = initial.fetch("concept").fetch("mastery")
    initial_risk = initial.fetch("risks").find { |risk| risk["id"].to_s == target_id.to_s }.fetch("risk")
    initial_plan = initial.fetch("study_blocks").map { |block| block.fetch("id") }

    start_transfer_flow(target_id)
    patch :action, params: { event: "answer_transfer", student_answer: "不确定" }, format: :json

    rejected = response.parsed_body
    expect(provider.calls.map(&:first)).to include(:validate_practice)
    expect(rejected.fetch("phase")).to eq("transfer")
    expect(rejected.fetch("concept").fetch("mastery")).to eq(initial_mastery)
    expect(rejected.fetch("risks").find { |risk| risk["id"].to_s == target_id.to_s }.fetch("risk")).to eq(initial_risk)
    expect(rejected.fetch("study_blocks").map { |block| block.fetch("id") }).to eq(initial_plan)
    expect(rejected.dig("learning_session", "transfer_validation", "verified")).to be(false)
  end
end
