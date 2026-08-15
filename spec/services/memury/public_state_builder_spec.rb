# frozen_string_literal: true

require "spec_helper"

describe Memury::PublicStateBuilder do
  let(:now) { Time.zone.parse("2026-08-08 09:00:00") }
  let(:state) { Memury::DemoState.build(now:) }

  it "derives Today, academic snapshot, risks, courses, and learner state from one persisted state" do
    public_state = described_class.call(state:, context: { type: "dashboard" }, now:)

    expect(public_state.fetch("today")).to include(
      "date" => "2026-08-08",
      "has_due_soon" => true,
      "has_overdue" => false
    )
    expect(public_state.fetch("time_zone")).to be_present
    expect(public_state.fetch("academic_snapshot")).to include(
      "course_count" => 6,
      "incomplete_assignment_count" => 13,
      "upcoming_exam_count" => 2
    )
    expect(public_state.fetch("risks")).to include(include("type" => "assignment", "course_id" => be_present))
    expect(public_state.fetch("risks")).to include(
      include("type" => "concept", "source" => include("source_platform" => "Learner State"))
    )
    expect(public_state.fetch("courses").map { |course| course.fetch("id") }).to include(
      "ME250",
      "CS101"
    )
    expect(public_state.dig("learner_state", "weak_concepts").first).to include(
      "name" => "平衡力与作用力—反作用力的区别",
      "source" => "Learner State",
      "official_or_inferred" => "Inferred"
    )
    expect(public_state.dig("next_action", "evidence")).to include(
      include("type" => "assignment"),
      include("type" => "learner_state"),
      include("type" => "exam", "source" => "Demo SIS", "official_or_inferred" => "Simulated")
    )
    expect(public_state.fetch("risks")).to include(
      include("type" => "exam", "source" => include("source_platform" => "Demo SIS", "official_or_inferred" => "Simulated"))
    )
  end

  it "scopes the recommendation to an explicit course context without replacing global state" do
    public_state = described_class.call(
      state:,
      context: { type: "course", course_id: "CS101" },
      now:
    )

    expect(public_state.dig("current_context", "type")).to eq("course")
    expect(public_state.dig("current_context", "course_id")).to eq("CS101")
    expect(public_state.dig("next_action", "course")).to eq("CS 101: Intro Computing")
    expect(public_state.fetch("assignments").length).to eq(19)
  end

  it "marks simulated demo courses explicitly and never invokes a provider" do
    public_state = described_class.call(state:, context: { type: "dashboard" }, now:)

    expect(public_state.fetch("courses")).to all(include("official_or_inferred" => "Simulated"))
    expect(public_state.dig("provenance", "state_source")).to include("Demo")
  end

  it "keeps completed assignments visible while choosing the next actionable assignment" do
    completed_state = state.deep_dup
    completed_state["completed_assignment_ids"] = ["ME250-HW4"]

    public_state = described_class.call(state: completed_state, context: { type: "dashboard" }, now:)

    expect(public_state.fetch("assignments").map { |item| item.fetch("id") }).to include("ME250-HW4")
    expect(public_state["assignments"].find { |item| item["id"] == "ME250-HW4" }).to include(
      "risk_reasons" => include("已完成本轮补强，风险已显著下降")
    )
    expect(public_state.dig("next_action", "assignment_id")).not_to eq("ME250-HW4")
    expect(public_state.dig("academic_snapshot", "incomplete_assignment_count")).to eq(12)
  end

  it "does not fall back to a different course for an explicit empty context" do
    public_state = described_class.call(
      state:,
      context: { type: "course", course_id: "canvas-course-without-memury-data" },
      now:
    )

    expect(public_state["next_action"]).to be_nil
    expect(public_state.dig("current_context", "course_id")).to eq("canvas-course-without-memury-data")
  end


  it "uses the Canvas course id to deduplicate matching Demo course metadata" do
    deduplicated_state = state.deep_stringify_keys
    assignment = deduplicated_state.fetch("assignments").first
    deduplicated_state["assignments"] = [
      assignment.merge("id" => "demo-copy", "course_id" => "ME250"),
      assignment.merge("id" => "42", "course_id" => "7", "official_or_inferred" => "Official")
    ]
    deduplicated_state["canvas"] = {
      "courses" => [{ "id" => "7", "name" => assignment.fetch("course_name") }]
    }

    public_state = described_class.call(state: deduplicated_state, context: { type: "dashboard" }, now:)

    expect(public_state.dig("academic_snapshot", "course_count")).to eq(1)
    expect(public_state.fetch("courses").map { |course| course.fetch("id") }).to eq(["7"])
  end

  it "keeps overdue work visible in risks but excludes it from the next best action" do
    overdue_state = state.deep_stringify_keys
    overdue_state["assignments"] = overdue_state.fetch("assignments").map do |assignment|
      assignment.merge("due_at" => (now - 1.hour).iso8601, "submitted" => false)
    end

    public_state = described_class.call(state: overdue_state, context: { type: "dashboard" }, now:)

    expect(public_state.fetch("risks")).to include(include("type" => "assignment", "status" => "overdue"))
    expect(public_state["next_action"]).to be_nil
  end
end
