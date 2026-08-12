# frozen_string_literal: true

require "spec_helper"

describe Memury::Teaching::DeterministicProvider do
  let(:state) { Memury::DemoState.build }
  let(:practice_context) { Memury::Teaching::PracticeContext.from_state(state) }

  it "builds planner and tutor contexts from only role-specific fields" do
    planner = Memury::Teaching::PlannerContext.from_state(state.merge("conversation_history" => ["private chat"]))
    expect(planner.to_h.keys).to match_array(%w[tasks deadlines exams submission_states time_budget knowledge_gaps verified_results risk_state plan_state])
    expect(planner.to_h).not_to have_key("conversation_history")

    tutor = Memury::Teaching::TutorContext.from_state(state, student_answer: "学生答案")
    expect(tutor.to_h).to include("knowledge_point", "question", "student_answer", "learner_state_summary")
    expect(tutor.to_h).not_to have_key("assignments")
    expect(tutor.to_h).not_to have_key("conversation_history")
  end

  it "keeps generator and validator contexts independent" do
    candidate = subject.generate_practice(practice_context)
    validator_context = Memury::Teaching::ValidatorContext.for_candidate(candidate:, context: practice_context)

    expect(candidate.expected_answer).to be_present
    expect(validator_context.to_h).not_to have_key("generator_private_reasoning")
    expect(validator_context.to_h).not_to have_key("learner_state_summary")
    expect(subject.validate_practice(validator_context)).to include_validation("passed", true)
  end

  it "rejects malformed candidates instead of treating them as validated" do
    context = Memury::Teaching::ValidatorContext.new(
      course_or_subject: "课程",
      knowledge_point: "知识点",
      question: "题目",
      candidate_prompt: "",
      candidate_expected_answer: "",
      candidate_explanation: "",
      difficulty: "transfer",
      source_materials: []
    )

    expect(subject.validate_practice(context)).to include_validation("failed", false)
  end

  it "validates a learner transfer independently from candidate generation" do
    candidate = subject.generate_practice(practice_context)
    context = Memury::Teaching::ValidatorContext.for_transfer(
      candidate:,
      context: practice_context,
      student_answer: candidate.expected_answer
    )

    result = subject.assess_transfer(context)
    expect(result.completed?).to be(true)
    expect(result.verified).to be(true)
    expect(result.source).to eq("deterministic_validator")
  end

  it "provides a deterministic no-key diagnosis and summary" do
    tutor = Memury::Teaching::TutorContext.from_state(state, student_answer: "我不知道")
    diagnosis = subject.diagnose(tutor)
    expect(diagnosis.source).to eq("rule_fallback")
    expect(diagnosis.answer_judgment).to eq("uncertain")

    summary = subject.summarize_evidence(
      Memury::Teaching::EvidenceContext.new(evidence: [{ "verified" => true }, { "verified" => false }])
    )
    expect(summary.to_h).to include("verified_count" => 1, "total_count" => 2)
  end

  it "turns the structured diagnosis into bounded progressive guidance" do
    tutor = Memury::Teaching::TutorContext.from_state(
      state.merge("diagnostic" => { "hint" => "先标出每个力作用的对象。" })
    )

    guidance = subject.guide(tutor)
    expect(guidance.layers.first).to eq("先标出每个力作用的对象。")
    expect(guidance.layers.length).to be <= 4
  end

  def subject
    described_class.new
  end

  def include_validation(status, verified)
    satisfy { |result| result.status == status && result.verified == verified }
  end
end

describe Memury::Teaching::OpenAiProvider do
  it "adapts the existing diagnosis service to the provider protocol" do
    result = instance_double(
      Memury::Ai::TeachingDiagnosisService::Result,
      diagnostic: {
        "diagnosis_summary" => "观察到概念混淆",
        "answer_judgment" => "incorrect",
        "misconception_type" => "conceptual",
        "evidence" => ["答案中的可观察线索"],
        "confidence" => 0.7,
        "verification_question" => "再解释一次",
        "hint" => "先找作用对象",
        "transfer_question" => "换个情境判断",
        "learner_state_suggestion" => { "skill" => "概念", "suggested_status" => "review", "reason" => "证据不足" }
      },
      source: "rule_fallback",
      fallback_reason: "OPENAI_API_KEY missing",
      compatibility_note: nil,
      latency_ms: 0
    )
    service = class_double(Memury::Ai::TeachingDiagnosisService, call: result)
    provider = described_class.new(diagnosis_service: service)
    context = Memury::Teaching::TutorContext.new(
      course_or_subject: "课程", knowledge_point: "知识点", question: "题目", scoring_basis: "标准",
      student_answer: "答案", learner_state_summary: {}, recent_misconceptions: [], course_materials: []
    )

    diagnosis = provider.diagnose(context)
    expect(diagnosis.source).to eq("rule_fallback")
    expect(diagnosis.fallback_reason).to eq("OPENAI_API_KEY missing")
  end
end
