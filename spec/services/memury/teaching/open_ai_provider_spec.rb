# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

describe Memury::Teaching::OpenAiProvider do
  include WebMock::API

  class RecordingStructuredClient
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def call(capability:, instructions:, input:, schema:, schema_version:, **options)
      @calls << {
        capability: capability,
        instructions: instructions,
        input: input,
        schema: schema,
        schema_version: schema_version,
        options: options
      }
      Memury::Ai::StructuredResponseClient::Result.new(
        data: @responses.fetch(capability),
        metadata: {
          "provider" => "openai",
          "capability" => capability,
          "schema_version" => schema_version,
          "request_id" => "req-#{capability}",
          "status" => "success"
        }
      )
    end
  end

  let(:state) { Memury::DemoState.build.deep_stringify_keys }
  let(:tutor_context) { Memury::Teaching::TutorContext.from_state(state, student_answer: "我混淆了两个受力对象") }
  let(:practice_context) { Memury::Teaching::PracticeContext.from_state(state) }
  let(:candidate) do
    Memury::Teaching::PracticeCandidate.new(
      id: "candidate-1",
      prompt: "换一个接触情境判断受力对象。",
      expected_answer: "两个力作用在不同物体上。",
      explanation: "先检查受力对象。",
      knowledge_point: practice_context.knowledge_point,
      difficulty: "transfer",
      question_type: "scenario",
      source_basis: "trusted course source",
      source: "openai"
    )
  end

  let(:responses) do
    {
      "guide" => {
        "level" => 2, "hint" => "先圈出受力物体。", "contains_direct_answer" => false,
        "misconception" => "conceptual", "next_step" => "再回答迁移题。", "confidence" => 0.8
      },
      "generate_practice" => {
        "prompt" => "在电梯情境中判断受力对象。", "knowledge_point" => practice_context.knowledge_point,
        "difficulty" => "transfer", "expected_answer" => "两个力作用在不同物体上。",
        "explanation" => "先检查受力对象。", "question_type" => "scenario", "source_basis" => "trusted course source"
      },
      "validate_practice" => {
        "verified" => true, "knowledge_point_match" => true, "difficulty_fit" => true,
        "self_consistent" => true, "answer_correct" => true, "explanation_consistent" => true,
        "answer_leak" => false, "transfer_suitable" => true, "validation_basis" => "trusted_course_source",
        "failure_reason_codes" => [], "confidence" => 0.93, "summary" => "候选题通过独立验证。"
      },
      "assess_transfer" => {
        "passed" => true, "independently_completed" => true, "hint_dependent" => false,
        "misconception_tags" => [], "scoring_basis" => "trusted course source",
        "mastery_delta_suggestion" => 0.2, "confidence" => 0.92, "reason_code" => "transfer_answer_validated",
        "validation_basis" => "trusted_course_source", "summary" => "迁移答案通过验证。"
      },
      "summarize_evidence" => {
        "verified_conclusions" => ["迁移题独立通过"], "unresolved_misconceptions" => [],
        "hint_dependence" => "none", "transfer_result" => "passed", "evidence_strength" => "strong",
        "planner_summary" => "可供 Planner 使用的最小摘要。", "confidence" => 0.9
      }
    }
  end

  it "uses independent strict structured paths for all six capabilities" do
    diagnosis_result = instance_double(
      Memury::Ai::TeachingDiagnosisService::Result,
      diagnostic: {
        "diagnosis_summary" => "观察到概念混淆", "answer_judgment" => "incorrect",
        "misconception_type" => "conceptual", "evidence" => ["受力对象未区分"], "confidence" => 0.7,
        "verification_question" => "哪个物体受力？", "hint" => "先标对象。",
        "transfer_question" => "换个情境判断。",
        "learner_state_suggestion" => { "skill" => "对象", "suggested_status" => "review", "reason" => "证据不足" }
      },
      source: "ai", fallback_reason: nil, compatibility_note: nil, latency_ms: 12,
      metadata: { "provider" => "openai", "capability" => "diagnose", "status" => "success" }
    )
    diagnosis_service = class_double(Memury::Ai::TeachingDiagnosisService, call: diagnosis_result)
    client = RecordingStructuredClient.new(responses)
    provider = described_class.new(diagnosis_service:, client:)

    diagnosis = provider.diagnose(tutor_context)
    guidance = provider.guide(tutor_context)
    generated = provider.generate_practice(practice_context)
    validator_context = Memury::Teaching::ValidatorContext.for_candidate(candidate: generated, context: practice_context)
    validation = provider.validate_practice(validator_context)
    transfer_context = Memury::Teaching::ValidatorContext.for_transfer(
      candidate: generated, context: practice_context, student_answer: generated.expected_answer,
      legacy_correct: true
    )
    transfer = provider.assess_transfer(transfer_context)
    summary = provider.summarize_evidence(
      Memury::Teaching::EvidenceContext.new(evidence: [{ "kind" => "transfer", "verified" => true, "payload" => { "summary" => "通过" } }])
    )

    expect([diagnosis.source, guidance.source, generated.source, validation.source, transfer.source, summary.source]).to eq(
      ["ai", "openai", "openai", "openai", "openai", "openai"]
    )
    expect(client.calls.map { |call| call.fetch(:capability) }).to eq(
      %w[guide generate_practice validate_practice assess_transfer summarize_evidence]
    )
    expect(client.calls.map { |call| call.fetch(:instructions) }.uniq.length).to eq(5)
    expect(client.calls.map { |call| call.fetch(:schema) }.uniq.length).to eq(5)
    client.calls.each do |call|
      expect(call.fetch(:schema).fetch("additionalProperties")).to be(false)
      expect(call.fetch(:schema_version)).to eq(Memury::Ai::TeachingCapabilitySchemas::VERSION)
    end

    validator_input = client.calls.find { |call| call[:capability] == "validate_practice" }.fetch(:input)
    expect(validator_input).not_to have_key("generator_private_reasoning")
    expect(validator_input).to include("candidate_expected_answer")
    transfer_input = client.calls.find { |call| call[:capability] == "assess_transfer" }.fetch(:input)
    expect(transfer_input).not_to have_key("legacy_correct")
  end

  it "fails closed for insufficient validator basis and keeps fallback metadata explicit" do
    client = RecordingStructuredClient.new(responses)
    provider = described_class.new(client:)
    context = Memury::Teaching::ValidatorContext.new(
      course_or_subject: "课程", knowledge_point: "知识点", question: "题目",
      candidate_prompt: candidate.prompt, candidate_expected_answer: candidate.expected_answer,
      candidate_explanation: candidate.explanation, difficulty: candidate.difficulty, source_materials: []
    )

    result = provider.validate_practice(context)
    expect(result.verified).to be(false)
    expect(result.reason_code).to eq("insufficient_validation_basis")
    expect(result.validation_basis).to eq("insufficient_basis")
    expect(client.calls).to be_empty
  end

  it "uses deterministic fallback when a structured call fails" do
    failing_client = instance_double(Memury::Ai::StructuredResponseClient)
    allow(failing_client).to receive(:call).and_raise(
      Memury::Ai::StructuredResponseClient::Error.new("bad schema", category: "schema_validation_failed")
    )
    provider = described_class.new(client: failing_client)

    result = provider.guide(tutor_context)
    expect(result.source).to eq("deterministic_fallback")
    expect(result.metadata).to include("status" => "fallback", "fallback_reason" => "schema_validation_failed")
  end

  it "keeps every structured capability available without provider configuration" do
    failing_client = instance_double(Memury::Ai::StructuredResponseClient)
    allow(failing_client).to receive(:call).and_raise(
      Memury::Ai::StructuredResponseClient::Error.new("missing config", category: "missing_configuration")
    )
    provider = described_class.new(client: failing_client)
    generated = provider.generate_practice(practice_context)

    results = [
      provider.guide(tutor_context),
      generated,
      provider.validate_practice(
        Memury::Teaching::ValidatorContext.for_candidate(candidate: generated, context: practice_context)
      ),
      provider.assess_transfer(
        Memury::Teaching::ValidatorContext.for_transfer(
          candidate: generated, context: practice_context, student_answer: generated.expected_answer
        )
      ),
      provider.summarize_evidence(
        Memury::Teaching::EvidenceContext.new(evidence: [{ "kind" => "transfer", "verified" => false }])
      )
    ]

    expect(generated.source).to eq("deterministic_template")
    expect(results).to all(satisfy { |result| result.source.to_s.in?(%w[deterministic_fallback deterministic_template deterministic_validator deterministic_provider]) })
    expect(results).to all(satisfy { |result| result.metadata.to_h.fetch("provider").to_s.start_with?("deterministic") })
    expect(failing_client).to have_received(:call).exactly(5).times
  end

  it "falls back before any network request when the API key is absent" do
    endpoint = "https://api.krill-ai.net/codex/v1/responses"
    env = {
      "MEMURY_AI_ENABLED" => "true",
      "OPENAI_BASE_URL" => "https://api.krill-ai.net/codex/v1",
      "MEMURY_AI_MODEL" => "gpt-test"
    }
    client = Memury::Ai::StructuredResponseClient.new(env:)
    provider = described_class.new(client:)

    result = provider.guide(tutor_context)

    expect(result.source).to eq("deterministic_fallback")
    expect(result.metadata).to include("fallback_reason" => "missing_configuration")
    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  it "sends each non-diagnosis capability as an independent Responses JSON Schema request" do
    endpoint = "https://api.krill-ai.net/codex/v1/responses"
    env = {
      "MEMURY_AI_ENABLED" => "true",
      "OPENAI_API_KEY" => "sk-test-only",
      "OPENAI_BASE_URL" => "https://api.krill-ai.net/codex/v1",
      "MEMURY_AI_MODEL" => "gpt-test"
    }
    logger_io = StringIO.new
    client = Memury::Ai::StructuredResponseClient.new(env:, logger: Logger.new(logger_io))
    provider = described_class.new(client:, diagnosis_service: instance_double(Memury::Ai::TeachingDiagnosisService))
    ordered = %w[guide generate_practice validate_practice assess_transfer summarize_evidence]
    observed = []

    responses_for = lambda do |capability|
      responses.fetch(capability)
    end
    envelope = lambda do |data|
      {
        "id" => "resp-test",
        "status" => "completed",
        "output" => [{
          "type" => "message",
          "status" => "completed",
          "content" => [{ "type" => "output_text", "text" => JSON.generate(data) }]
        }]
      }
    end

    stub_request(:post, endpoint).with do |request|
      body = JSON.parse(request.body)
      format = body.fetch("text").fetch("format")
      capability = format.fetch("name").delete_prefix("memury_")
      observed << body
      expect(ordered).to include(capability)
      expect(body.fetch("store")).to be(false)
      expect(format.fetch("type")).to eq("json_schema")
      expect(format.fetch("strict")).to be(true)
      expect(format.fetch("schema")).to eq(Memury::Ai::TeachingCapabilitySchemas.schema(capability))
      true
    end.to_return(*ordered.map { |capability| { status: 200, body: envelope.call(responses_for.call(capability)).to_json } })

    guidance = provider.guide(tutor_context)
    generated = provider.generate_practice(practice_context)
    validator = provider.validate_practice(
      Memury::Teaching::ValidatorContext.for_candidate(candidate: generated, context: practice_context)
    )
    transfer = provider.assess_transfer(
      Memury::Teaching::ValidatorContext.for_transfer(
        candidate: generated, context: practice_context, student_answer: generated.expected_answer, hint_dependent: false
      )
    )
    summary = provider.summarize_evidence(
      Memury::Teaching::EvidenceContext.new(evidence: [{ "kind" => "transfer", "verified" => true }])
    )

    expect([guidance.source, generated.source, validator.source, transfer.source, summary.source]).to all(eq("openai"))
    expect(observed.map { |body| body.dig("text", "format", "name") }).to eq(ordered.map { |name| "memury_#{name}" })
    expect(WebMock).to have_requested(:post, endpoint).times(ordered.length)
  end

  it "does not wash an AI candidate as verified when the independent validator is unavailable" do
    failing_client = instance_double(Memury::Ai::StructuredResponseClient)
    allow(failing_client).to receive(:call).and_raise(
      Memury::Ai::StructuredResponseClient::Error.new("validator timeout", category: "timeout")
    )
    provider = described_class.new(client: failing_client)

    result = provider.validate_practice(
      Memury::Teaching::ValidatorContext.for_candidate(candidate:, context: practice_context)
    )

    expect(result.verified).to be(false)
    expect(result.reason_code).to eq("validator_unavailable")
    expect(result.validation_basis).to eq("insufficient_basis")
    expect(result.metadata).to include("provider" => "deterministic_fallback", "status" => "fallback")
  end
end
