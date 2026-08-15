# frozen_string_literal: true

require "digest"

module Memury
  module Learning
    # Minimal write surface for a nonlinear learning path. Parent links live
    # on the real Step input and never exist only in browser memory.
    class GraphCommandService
      class InvalidCommand < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      class << self
        def continue!(**attributes)
          new(**attributes).continue!
        end

        def select!(user:, assignment_ref:, node_id:)
          new(user:, assignment_ref:, parent_node_id: node_id).select!
        end
      end

      def initialize(user:, assignment_ref:, parent_node_id:, question: nil, request_id: nil)
        @user = user
        @assignment_ref = assignment_ref.to_s.presence
        @parent_node_id = parent_node_id.to_s
        @question = question.to_s.squish
        @request_id = request_id.to_s
      end

      def continue!
        raise InvalidCommand, "question_required" unless question.length.between?(2, 240)
        raise InvalidCommand, "request_id_invalid" unless request_id.match?(/\A[[:alnum:].:_-]{8,100}\z/)

        session.with_lock do
          parent_step, branch_kind = resolve_parent!
          idempotency_scope = [user.id, session.id, "continue", request_id].join(":")
          key = "graph-branch-#{Digest::SHA256.hexdigest(idempotency_scope)[0, 24]}"
          step = session.steps.find_by(idempotency_key: key)
          unless step
            step = session.steps.create!(
              kind: "student_question",
              sequence: session.steps.maximum(:sequence).to_i + 1,
              status: "completed",
              idempotency_key: key,
              started_at: Time.zone.now,
              ended_at: Time.zone.now,
              input: {
                "question" => question,
                "parent_step_id" => parent_step&.id,
                "parent_node_id" => parent_node_id,
                "branch_kind" => branch_kind
              }.compact,
              output: { "safe_summary" => question.truncate(220) }
            )
            session.evidences.create!(
              step:,
              kind: "student_question",
              fingerprint: Digest::SHA256.hexdigest([session.id, step.id, "student_question"].join(":")),
              source: "student",
              verified: false,
              confidence: nil,
              observed_at: Time.zone.now,
              payload: { "question" => question.truncate(500), "parent_node_id" => parent_node_id }
            )
          end
          store_current!("step-#{step.id}")
          step
        end
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def select!
        projection = GraphProjection.call(user:, assignment_ref:)
        raise InvalidCommand, "learning_session_not_found" if projection["learning_session_id"].blank?
        raise InvalidCommand, "node_not_found" unless projection.fetch("nodes").any? { |node| node["id"] == parent_node_id }

        session.with_lock { store_current!(parent_node_id) }
        parent_node_id
      end

      private

      attr_reader :user, :assignment_ref, :parent_node_id, :question, :request_id

      def session
        @session ||= begin
          scope = Memury::Session.where(user:).order(started_at: :desc)
          found = if assignment_ref
                    scope.detect do |candidate|
                      candidate.assignment_ref.to_s == assignment_ref || candidate.assignment_id.to_s == assignment_ref
                    end
                  else
                    scope.first
                  end
          found || raise(InvalidCommand, "learning_session_not_found")
        end
      end

      def resolve_parent!
        if parent_node_id == "session-#{session.id}"
          return [nil, "root"]
        end

        if (match = parent_node_id.match(/\Astep-(\d+)\z/))
          step = session.steps.find_by(id: match[1])
          return [step, "continuation"] if step
        end

        if (match = parent_node_id.match(/\Aevidence-(\d+)\z/))
          evidence = session.evidences.find_by(id: match[1])
          return [evidence.step, "continuation"] if evidence&.step
        end

        raise InvalidCommand, "parent_node_invalid"
      end

      def store_current!(node_id)
        session.metadata = session.metadata.to_h.merge("current_learning_graph_node_id" => node_id)
        session.save!
      end
    end
  end
end
