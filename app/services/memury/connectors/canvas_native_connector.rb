# frozen_string_literal: true

module Memury
  module Connectors
    class CanvasNativeConnector < BaseConnector
      def call
        courses = user.enrollments.current.active.student.map(&:course).uniq
        {
          courses: courses.map { |course| course_payload(course) },
          assignments: courses.flat_map { |course| assignment_payloads(course) },
          synced_at: now.iso8601
        }
      end

      private

      def course_payload(course)
        { id: course.id, name: course.name }.merge(provenance("Canvas", course.id, url: "/courses/#{course.id}"))
      end

      def assignment_payloads(course)
        course.assignments.published.where.not(due_at: nil).order(:due_at).limit(20).map do |assignment|
          submission = assignment.submissions.where(user_id: user.id).first
          hours_left = [(assignment.due_at - now) / 1.hour, 0].max
          deadline_risk = (1.0 - (hours_left / 168.0)).clamp(0.1, 1.0)
          weakness = submission&.score && assignment.points_possible.to_f.positive? ? 1.0 - (submission.score / assignment.points_possible.to_f) : 0.65
          {
            id: assignment.id, course_id: course.id, course_name: course.name, title: assignment.title,
            due_at: assignment.due_at&.iso8601, points_possible: assignment.points_possible,
            submitted: submission&.submitted?, score: submission&.score,
            risk: (deadline_risk * weakness.clamp(0.0, 1.0)).round(2)
          }.merge(provenance("Canvas", assignment.id, url: "/courses/#{course.id}/assignments/#{assignment.id}"))
        end
      end
    end
  end
end
