# frozen_string_literal: true

require "digest"
require "json"

module Memury
  module Learning
    # Persists the auditable Session -> Step -> Evidence spine. The recorder
    # only stores whitelisted, structured payloads; provider prompts, raw
    # responses, and private reasoning never enter the trace.
    class TraceRecorder
      EVENT_KINDS = {
        "start_study_block" => "recall",
        "answer_recall" => "answer",
        "answer_verification" => "validation",
        "request_hint" => "hint",
        "start_transfer" => "practice_generation",
        "answer_transfer" => "transfer_assessment",
        "complete_block" => "replan",
        "skip_block" => "replan",
        "reschedule_block" => "replan",
        "return_home" => "replan"
      }.freeze

      # A state-changing learning event cannot silently continue when its
      # audit spine is unavailable.  Read-only/legacy events may still use
      # the compatibility degradation below, but verification events must
      # fail closed so Learner State can never outlive its evidence.
      class StorageUnavailable < StandardError
        attr_reader :reason

        def initialize(reason = "trace_storage_unavailable")
          @reason = reason.to_s
          super(@reason)
        end
      end

      class << self
        def available?
          Memury::Session.table_exists? && Memury::Step.table_exists? && Memury::Evidence.table_exists?
        rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
          false
        end

        def record_event!(user:, state:, event:, params:, before_state:, now: Time.zone.now, required: false)
          unless available?
            raise StorageUnavailable if required

            return
          end

          learning_session = state["learning_session"] ||= {}
          session = find_or_create_session!(user:, state:, learning_session:, event:, now:)
          learning_session["trace_session_id"] = session.id.to_s

          payloads = evidence_payloads(state:, event:, params:)
          step_payload = step_input(event:, params:)
          step_key = fingerprint(session.id, event, step_payload)
          step = session.steps.find_or_create_by!(idempotency_key: step_key) do |candidate|
            candidate.kind = EVENT_KINDS.fetch(event, "event")
            candidate.sequence = session.steps.maximum(:sequence).to_i + 1
            candidate.started_at = now
            candidate.ended_at = now
            candidate.input = step_payload
            candidate.output = step_output(state:, before_state:, event:)
            candidate.status = if event == "answer_transfer"
                                 transfer_validation_verified?(state) ? "completed" : "failed"
                               else
                                 "completed"
                               end
          end

          evidence_records = payloads.map do |payload|
            payload = payload.stringify_keys
            evidence_key = fingerprint(session.id, payload.fetch("kind"), payload.fetch("payload"))
            session.evidences.find_or_create_by!(fingerprint: evidence_key) do |evidence|
              evidence.step = step
              evidence.kind = payload.fetch("kind")
              evidence.source = payload.fetch("source")
              evidence.verified = payload.fetch("verified", false)
              evidence.confidence = payload["confidence"]
              evidence.observed_at = now
              evidence.payload = payload.fetch("payload")
            end
          end

          # The decision log is created by the orchestration layer before the
          # trace is persisted.  Bind it to the actual Evidence row here,
          # inside the same transaction, rather than a descriptive string.
          if event == "answer_transfer"
            trigger = evidence_records.find { |evidence| evidence.kind == "transfer_validation" }
            bind_trigger_evidence!(state:, step:, evidence: trigger) if trigger
          end

          if state.dig("learning_session", "completed_at").present? || state["phase"] == "complete"
            session.status = "completed"
            session.result = state.dig("learning_session", "transfer_correct") ? "transfer_passed" : "transfer_failed"
            session.ended_at ||= now
            session.duration_seconds ||= [(session.ended_at - session.started_at).to_i, 0].max
          end
          session.summary = state.dig("concept", "reason").presence || session.summary
          session.metadata = session.metadata.to_h.merge("last_event" => event, "phase" => state["phase"])
          session.save!
          session
        rescue ActiveRecord::RecordNotUnique
          retry
        rescue ActiveRecord::RecordInvalid
          raise StorageUnavailable if required

          raise
        rescue ActiveRecord::StatementInvalid => e
          raise StorageUnavailable if required
          raise unless missing_trace_table_error?(e)

          Rails.logger.warn("Memury trace unavailable: #{e.class}")
          nil
        rescue ActiveRecord::NoDatabaseError => e
          raise StorageUnavailable if required

          Rails.logger.warn("Memury trace unavailable: #{e.class}")
          nil
        end

        private

        def find_or_create_session!(user:, state:, learning_session:, event:, now:)
          key = learning_session["trace_session_key"].presence
          unless key
            seed = [user.id, learning_session["target_assignment_id"], learning_session["started_at"], event].join(":")
            key = "memury-#{Digest::SHA256.hexdigest(seed)[0, 24]}"
            learning_session["trace_session_key"] = key
          end
          assignment_ref = learning_session["target_assignment_id"].to_s.presence
          course_ref = learning_session["course_id"].to_s.presence
          Memury::Session.find_or_create_by!(idempotency_key: key) do |session|
            session.user = user
            session.course_ref = course_ref
            session.assignment_ref = assignment_ref
            session.study_block_id = learning_session["originating_study_block"].to_s.presence
            session.objective = state.dig("concept", "name").presence || "Memury learning objective"
            session.started_at = parse_time(learning_session["started_at"]) || now
            session.metadata = {
              "source_type" => learning_session["source_type"],
              "source_id" => learning_session["source_id"],
              "concept_id" => learning_session["concept_id"],
              "trigger_reason" => learning_session["trigger_reason"]
            }.compact
          end
        end

        def evidence_payloads(state:, event:, params:)
          session = state.fetch("learning_session", {})
          case event
          when "start_study_block"
            [{ kind: "session_started",
               source: "Memury planner",
               verified: true,
               payload: { "assignment_id" => session["target_assignment_id"], "source_type" => session["source_type"] }.compact }]
          when "answer_recall"
            payloads = [{ kind: "student_answer",
                          source: "student",
                          verified: false,
                          payload: { "answer" => param_value(params, :student_answer).to_s.truncate(2000), "question" => session["recall_question"] }.compact }]
            if state["diagnostic"].is_a?(Hash)
              payloads << { kind: "diagnosis",
                            source: state.dig("diagnostic", "source").presence || "rule_fallback",
                            verified: true,
                            confidence: state.dig("diagnostic", "confidence"),
                            payload: state.fetch("diagnostic").slice(
                              "diagnosis_summary", "answer_judgment", "misconception_type", "evidence", "confidence"
                            ) }
            end
            payloads
          when "answer_verification"
            [{ kind: "hypothesis_confirmation",
               source: "student",
               verified: false,
               payload: { "hypothesis" => state["verified_hypothesis"] }.compact }]
          when "request_hint"
            [{ kind: "hint",
               source: "Memury tutor",
               verified: true,
               payload: { "level" => session["hint_level"], "hint" => session["active_hint"] }.compact }]
          when "start_transfer"
            [{ kind: "practice_validation",
               source: state.dig("learning_session", "practice_validation", "source").presence || "deterministic_validator",
               verified: state.dig("learning_session", "practice_validation", "verified") == true,
               confidence: state.dig("learning_session", "practice_validation", "confidence"),
               payload: state.dig("learning_session", "practice_validation").to_h.except("expected_answer") }]
          when "answer_transfer"
            payloads = [{ kind: "transfer_validation",
                          source: session.dig("transfer_validation", "source").presence || "deterministic_validator",
                          verified: session.dig("transfer_validation", "verified") == true,
                          confidence: session.dig("transfer_validation", "confidence"),
                          payload: session["transfer_validation"].to_h.except("expected_answer") }]
            if !param_value(params, :correct).nil? && param_value(params, :student_answer).to_s.strip.blank? && param_value(params, :transfer_answer).to_s.strip.blank?
              payloads << { kind: "legacy_demo_signal",
                            source: "legacy_demo_signal",
                            verified: false,
                            payload: { "correct" => ActiveModel::Type::Boolean.new.cast(param_value(params, :correct)),
                                       "validation_basis" => "legacy_demo_signal" } }
            end
            if session["evidence_summary"].is_a?(Hash)
              payloads << { kind: "evidence_summary",
                            source: session.dig("evidence_summary", "source").presence || "Memury teaching provider",
                            verified: session.dig("transfer_validation", "verified") == true,
                            confidence: session.dig("evidence_summary", "confidence"),
                            payload: session.fetch("evidence_summary").slice("summary", "verified_count", "total_count", "confidence") }
            end
            payloads
          when "complete_block", "skip_block", "reschedule_block", "return_home"
            [{ kind: "replan",
               source: "Memury Risk Engine",
               verified: true,
               payload: { "event" => event, "block_id" => param_value(params, :block_id), "decision" => state.fetch("decision_logs", []).last }.compact }]
          else
            [{ kind: "event", source: "Memury", verified: false, payload: { "event" => event } }]
          end
        end

        def step_input(event:, params:)
          raw_params = if params.respond_to?(:to_unsafe_h)
                         params.to_unsafe_h
                       elsif params.respond_to?(:to_h)
                         params.to_h
                       else
                         params
                       end
          raw_params.stringify_keys.slice(
            "event",
            "assignment_id",
            "block_id",
            "source_type",
            "source_id",
            "course_id",
            "concept_id",
            "trigger_reason",
            "originating_study_block",
            "student_answer",
            "correct",
            "duration_minutes",
            "starts_at"
          ).merge("event" => event)
        end

        def param_value(params, key)
          return params[key] if params.respond_to?(:key?) && params.key?(key)
          return params[key.to_s] if params.respond_to?(:key?) && params.key?(key.to_s)

          nil
        end

        def step_output(state:, before_state:, event:)
          {
            "phase_before" => before_state["phase"],
            "phase_after" => state["phase"],
            "concept_before" => before_state["concept"].to_h.slice("mastery", "confidence"),
            "concept_after" => state["concept"].to_h.slice("mastery", "confidence"),
            "event" => event,
            "decision_log" => state.fetch("decision_logs", []).last
          }.compact
        end

        def bind_trigger_evidence!(state:, step:, evidence:)
          decision = state.fetch("decision_logs", []).last
          return unless decision.is_a?(Hash)

          decision["trigger_evidence_id"] = evidence.id
          decision["trigger_evidence"] = evidence.kind
          step.output = step.output.to_h.merge("decision_log" => decision)
          step.save!
        end

        def transfer_validation_verified?(state)
          state.dig("learning_session", "transfer_validation", "verified") == true
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def missing_trace_table_error?(error)
          error.message.match?(/(?:relation|table).*memury_learning_(?:sessions|steps|evidence).*does not exist/i)
        end

        def fingerprint(*parts)
          canonical = parts.map { |part| canonicalize(part) }
          Digest::SHA256.hexdigest(JSON.generate(canonical))
        end

        def canonicalize(value)
          case value
          when Hash
            value.to_h.sort_by { |key, _| key.to_s }.to_h { |key, nested| [key.to_s, canonicalize(nested)] }
          when Array
            value.map { |nested| canonicalize(nested) }
          else
            value
          end
        end
      end
    end
  end
end
