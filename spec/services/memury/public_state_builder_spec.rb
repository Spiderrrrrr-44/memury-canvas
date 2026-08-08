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
    expect(public_state.fetch("academic_snapshot")).to include(
      "course_count" => 2,
      "incomplete_assignment_count" => 5,
      "upcoming_exam_count" => 1
    )
    expect(public_state.fetch("risks").first).to include("type" => "assignment", "course_id" => "demo-course-mechanics")
    expect(public_state.fetch("risks")).to include(
      include("type" => "concept", "source" => include("source_platform" => "Learner State"))
    )
    expect(public_state.fetch("courses").map { |course| course.fetch("id") }).to include(
      "demo-course-mechanics",
      "demo-course-programming"
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
      context: { type: "course", course_id: "demo-course-programming" },
      now:
    )

    expect(public_state.dig("current_context", "type")).to eq("course")
    expect(public_state.dig("current_context", "course_id")).to eq("demo-course-programming")
    expect(public_state.dig("next_action", "course")).to eq("程序设计实践")
    expect(public_state.fetch("assignments").length).to eq(5)
  end

  it "marks simulated demo courses explicitly and never invokes a provider" do
    public_state = described_class.call(state:, context: { type: "dashboard" }, now:)

    expect(public_state.fetch("courses")).to all(include("official_or_inferred" => "Simulated"))
    expect(public_state.dig("provenance", "state_source")).to include("Demo")
  end

  it "keeps completed assignments visible while choosing the next actionable assignment" do
    completed_state = state.deep_dup
    completed_state["completed_assignment_ids"] = ["mech-force"]

    public_state = described_class.call(state: completed_state, context: { type: "dashboard" }, now:)

    expect(public_state.fetch("assignments").map { |item| item.fetch("id") }).to include("mech-force")
    expect(public_state["assignments"].find { |item| item["id"] == "mech-force" }).to include(
      "risk_reasons" => include("已完成本轮补强，风险已显著下降")
    )
    expect(public_state.dig("next_action", "assignment_id")).not_to eq("mech-force")
    expect(public_state.dig("academic_snapshot", "incomplete_assignment_count")).to eq(4)
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
end
