# frozen_string_literal: true

require "digest"
require_relative "q_graph_conversation_service"

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

      def initialize(user:, assignment_ref:, parent_node_id:, question: nil, request_id: nil,
                     document_title: nil, document_excerpt: nil, locale: nil)
        @user = user
        @assignment_ref = assignment_ref.to_s.presence
        @parent_node_id = parent_node_id.to_s
        @question = question.to_s.squish
        @request_id = request_id.to_s
        @document_title = document_title.to_s.squish.truncate(160)
        @document_excerpt = document_excerpt.to_s.squish.truncate(1_200)
        @locale = locale.to_s
      end

      def continue!
        raise InvalidCommand, "question_required" unless question.length.between?(2, 240)
        raise InvalidCommand, "request_id_invalid" unless request_id.match?(/\A[[:alnum:].:_-]{8,100}\z/)

        parent_step, branch_kind = resolve_parent!
        question_key = idempotency_key("question")
        response_key = idempotency_key("response")
        existing_response = session.steps.find_by(idempotency_key: response_key)
        reply = existing_response&.output.presence || conversation_service.reply(
          document_title: effective_document_title,
          document_excerpt: effective_document_excerpt,
          question:,
          conversation: conversation_messages,
          locale:
        )

        session.with_lock do
          step = session.steps.find_by(idempotency_key: question_key)
          unless step
            step = session.steps.create!(
              kind: "student_question",
              sequence: session.steps.maximum(:sequence).to_i + 1,
              status: "completed",
              idempotency_key: question_key,
              started_at: Time.zone.now,
              ended_at: Time.zone.now,
              input: {
                "question" => question,
                "parent_step_id" => parent_step&.id,
                "parent_node_id" => parent_node_id,
                "branch_kind" => branch_kind,
                "document_title" => effective_document_title,
                "locale" => normalized_locale
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

          response = session.steps.find_by(idempotency_key: response_key) || session.steps.create!(
            kind: "tutor_response",
            sequence: session.steps.maximum(:sequence).to_i + 1,
            status: "completed",
            idempotency_key: response_key,
            started_at: Time.zone.now,
            ended_at: Time.zone.now,
            input: {
              "parent_step_id" => step.id,
              "parent_node_id" => "step-#{step.id}",
              "branch_kind" => "response",
              "document_title" => effective_document_title,
              "locale" => normalized_locale
            },
            output: reply.slice(
              "answer", "follow_up", "conversation_summary", "key_points", "source", "provider_metadata"
            )
          )
          session.update!(
            summary: reply["conversation_summary"],
            metadata: session.metadata.to_h.merge(
              "current_learning_graph_node_id" => "step-#{response.id}",
              "q_graph_document_title" => effective_document_title,
              "q_graph_document_excerpt" => effective_document_excerpt,
              "q_graph_locale" => normalized_locale,
              "q_graph_key_points" => Array(reply["key_points"]).first(5)
            )
          )
          response
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

      attr_reader :user, :assignment_ref, :parent_node_id, :question, :request_id,
                  :document_title, :document_excerpt, :locale

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
          found || create_document_session!
        end
      end

      def create_document_session!
        raise InvalidCommand, "learning_session_not_found" unless assignment_ref && parent_node_id == "document-root"

        key = "q-graph-session-#{Digest::SHA256.hexdigest([user.id, assignment_ref].join(":"))[0, 24]}"
        Memury::Session.find_or_create_by!(idempotency_key: key) do |record|
          record.user = user
          record.assignment_ref = assignment_ref
          record.objective = effective_document_title
          record.status = "active"
          record.started_at = Time.zone.now
          record.metadata = {
            "q_graph_document_title" => effective_document_title,
            "q_graph_document_excerpt" => effective_document_excerpt,
            "q_graph_locale" => normalized_locale
          }
        end
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def resolve_parent!
        if parent_node_id == "document-root"
          return [nil, "root"]
        end

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

      def idempotency_key(kind)
        scope = [user.id, session.id, "q-graph", kind, request_id].join(":")
        "q-graph-#{kind}-#{Digest::SHA256.hexdigest(scope)[0, 24]}"
      end

      def conversation_messages
        session.steps.order(:sequence, :id).filter_map do |step|
          case step.kind
          when "student_question"
            { "role" => "user", "content" => step.input.to_h.deep_stringify_keys["question"] }
          when "tutor_response"
            { "role" => "assistant", "content" => step.output.to_h.deep_stringify_keys["answer"] }
          end
        end
      end

      def conversation_service
        @conversation_service ||= QGraphConversationService.new
      end

      def effective_document_title
        document_title.presence || @session&.metadata.to_h&.dig("q_graph_document_title").presence ||
          (normalized_locale == "zh-CN" ? "当前文档" : "Current document")
      end

      def effective_document_excerpt
        document_excerpt.presence || @session&.metadata.to_h&.dig("q_graph_document_excerpt").to_s
      end

      def normalized_locale
        locale.downcase.start_with?("zh") ? "zh-CN" : "en"
      end
    end
  end
end
