# frozen_string_literal: true

require "spec_helper"

describe Memury::Connectors::CanvasNativeConnector do
  it "only returns courses in the current student's active enrollments" do
    student_in_course(active_all: true)
    visible = @course
    hidden = course_factory(active_all: true)
    assignment_model(course: visible, due_at: 1.day.from_now)
    assignment_model(course: hidden, due_at: 1.day.from_now)

    result = described_class.new(user: @student).call

    expect(result[:courses].pluck(:id)).to eq([visible.id])
    expect(result[:assignments].pluck(:course_id)).to all(eq(visible.id))
    expect(result[:assignments].first).to include(source_platform: "Canvas", official_or_inferred: "Official", confidence: 1.0)
  end
end
