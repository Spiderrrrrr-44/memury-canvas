# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

describe Memury::Ai::StructuredResponseClient do
  include WebMock::API

  let(:endpoint) { "https://api.krill-ai.net/codex/v1/responses" }
  let(:env) do
    {
      "MEMURY_AI_ENABLED" => "true",
      "OPENAI_API_KEY" => "sk-test-only",
      "OPENAI_BASE_URL" => "https://api.krill-ai.net/codex/v1",
      "MEMURY_AI_MODEL" => "gpt-test"
    }
  end
  let(:schema) { Memury::Ai::TeachingCapabilitySchemas::GUIDE }
  let(:valid_data) do
    {
      "level" => 1,
      "hint" => "先找出受力对象。",
      "contains_direct_answer" => false,
      "misconception" => "conceptual",
      "next_step" => "再回答迁移题。",
      "confidence" => 0.8
    }
  end
  let(:logger_io) { StringIO.new }
  let(:client) { described_class.new(env:, logger: Logger.new(logger_io)) }

  around do |example|
    WebMock.disable_net_connect!
    example.run
  ensure
    WebMock.allow_net_connect!
  end

  def envelope(data, status: "completed")
    {
      "id" => "resp-test-1",
      "status" => status,
      "output" => [{
        "type" => "message",
        "status" => "completed",
        "content" => [{ "type" => "output_text", "text" => JSON.generate(data) }]
      }],
      "usage" => { "input_tokens" => 10, "output_tokens" => 20, "total_tokens" => 30 }
    }
  end

  it "sends one strict structured request and returns bounded metadata" do
    stub_request(:post, endpoint).with do |request|
      body = JSON.parse(request.body)
      expect(body["model"]).to eq("gpt-test")
      expect(body["store"]).to be(false)
      expect(body.dig("text", "format", "name")).to eq("memury_guide")
      expect(body.dig("text", "format", "strict")).to be(true)
      expect(body.dig("text", "format", "schema", "additionalProperties")).to be(false)
      expect(body["input"]).to include("student_answer")
      true
    end.to_return(status: 200, headers: { "x-request-id" => "req-test-1" }, body: envelope(valid_data).to_json)

    result = client.call(
      capability: "guide", instructions: "Return JSON only.", input: { "student_answer" => "answer" },
      schema:, schema_version: Memury::Ai::TeachingCapabilitySchemas::VERSION
    )

    expect(result.data).to eq(valid_data)
    expect(result.metadata).to include(
      "provider" => "openai", "status" => "success", "request_id" => "req-test-1",
      "schema_version" => Memury::Ai::TeachingCapabilitySchemas::VERSION,
      "token_usage" => { "input_tokens" => 10, "output_tokens" => 20, "total_tokens" => 30 }
    )
    expect(logger_io.string).not_to include("sk-test-only")
  end

  it "rejects malformed JSON and strict schema violations" do
    stub_request(:post, endpoint).to_return(
      { status: 200, body: envelope({ "not" => "guide" }).to_json },
      { status: 200, body: envelope(valid_data.merge("unexpected" => true)).to_json }
    )

    first_error = catch_error { client.call(capability: "guide", instructions: "x", input: {}, schema:, schema_version: "v1") }
    second_error = catch_error { client.call(capability: "guide", instructions: "x", input: {}, schema:, schema_version: "v1") }
    expect(first_error.category).to eq("schema_validation_failed")
    expect(second_error.category).to eq("schema_validation_failed")
  end

  it "rejects an invalid object for every teaching capability schema" do
    invalid = { "unexpected" => true }
    Memury::Ai::TeachingCapabilitySchemas::SCHEMAS.each_key do |capability|
      stub_request(:post, endpoint).to_return(status: 200, body: envelope(invalid).to_json)

      error = catch_error do
        client.call(
          capability:, instructions: "x", input: {},
          schema: Memury::Ai::TeachingCapabilitySchemas.schema(capability), schema_version: "v1"
        )
      end
      expect(error.category).to eq("schema_validation_failed"), capability
    end
  end

  it "classifies refusal, incomplete, and provider failures without exposing response bodies" do
    stub_request(:post, endpoint).to_return(
      { status: 200, body: {
        "status" => "completed", "output" => [{ "type" => "message", "status" => "completed",
          "content" => [{ "type" => "refusal", "refusal" => "private reason" }] }]
      }.to_json },
      { status: 200, body: { "status" => "incomplete", "incomplete_details" => { "reason" => "length" } }.to_json },
      { status: 500, body: { "error" => "provider secret" }.to_json }
    )

    refusal = catch_error { client.call(capability: "guide", instructions: "x", input: {}, schema:, schema_version: "v1") }
    incomplete = catch_error { client.call(capability: "guide", instructions: "x", input: {}, schema:, schema_version: "v1") }
    http = catch_error { client.call(capability: "guide", instructions: "x", input: {}, schema:, schema_version: "v1") }
    expect(refusal.category).to eq("refusal")
    expect(incomplete.category).to eq("incomplete_response")
    expect(http.category).to eq("http_500")
    expect([refusal.message, incomplete.message, http.message].join(" ")).not_to include("provider secret", "private reason")
  end

  def catch_error
    yield
    raise "expected StructuredResponseClient::Error"
  rescue Memury::Ai::StructuredResponseClient::Error => e
    e
  end
end
