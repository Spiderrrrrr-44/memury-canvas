# frozen_string_literal: true

require "spec_helper"
require "securerandom"

describe Memury::PublicStateSerializer do
  def recursive_key_paths(value, target_key, path = [], matches = [])
    case value
    when Hash
      value.each do |key, nested|
        current_path = path + [key.to_s]
        matches << current_path.join(".") if key.to_s == target_key
        recursive_key_paths(nested, target_key, current_path, matches)
      end
    when Array
      value.each_with_index do |nested, index|
        recursive_key_paths(nested, target_key, path + [index.to_s], matches)
      end
    end
    matches
  end

  it "recursively removes browser-sensitive keys without mutating the source state" do
    marker = "memury-secret-#{SecureRandom.hex(8)}"
    state = {
      "concept" => {
        "name" => "平衡力与作用力—反作用力的区别",
        "reference_answer" => marker
      },
      "diagnostic" => {
        "provider_prompt" => "prompt #{marker}",
        "provider_raw_body" => "body #{marker}",
        "provider_response" => {
          "stack_trace" => "trace #{marker}",
          "nested" => [
            {"reference_answer" => marker},
            {"authorization" => "Bearer #{marker}"}
          ]
        }
      },
      "evidence" => [
        {"title" => "observed", "notes" => "student evidence"}
      ],
      "learning_session" => {
        "last_transfer_request_key" => marker,
        "last_transfer_processed_at" => "2026-08-10T10:00:00Z"
      }
    }

    serialized = described_class.call(state)

    expect(state.dig("concept", "reference_answer")).to eq(marker)
    expect(state.dig("diagnostic", "provider_prompt")).to include(marker)
    expect(state.dig("diagnostic", "provider_response", "nested", 0, "reference_answer")).to eq(marker)
    expect(serialized.dig("concept", "reference_answer")).to be_nil
    expect(recursive_key_paths(serialized, "reference_answer")).to be_empty
    expect(recursive_key_paths(serialized, "provider_prompt")).to be_empty
    expect(recursive_key_paths(serialized, "provider_raw_body")).to be_empty
    expect(recursive_key_paths(serialized, "stack_trace")).to be_empty
    expect(recursive_key_paths(serialized, "authorization")).to be_empty
    expect(recursive_key_paths(serialized, "last_transfer_request_key")).to be_empty
    expect(recursive_key_paths(serialized, "last_transfer_processed_at")).to be_empty
    expect(JSON.generate(serialized)).not_to include(marker)
    expect(serialized.dig("diagnostic", "provider_response")).to be_nil
    expect(serialized.dig("evidence", 0, "notes")).to eq("student evidence")
  end
end
