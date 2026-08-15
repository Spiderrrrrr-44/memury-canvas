# frozen_string_literal: true

module Memury
  module Learning
    # Read-only, public-safe projection of the existing Session/Step/Evidence
    # audit spine. It is deliberately not a second graph data store.
    class GraphProjection
      TRUSTED_BASES = AcademicEvidenceProjector::TRUSTED_BASES
      STEP_KINDS = {
        "recall" => ["learning_goal", "Recall 检查"],
        "answer" => ["student_question", "学生作答"],
        "student_question" => ["student_question", "继续提问"],
        "validation" => ["verification", "错因验证"],
        "hint" => ["intervention", "分层提示"],
        "practice_generation" => ["transfer_task", "迁移任务"],
        "transfer_assessment" => ["verification_result", "迁移验证"],
        "replan" => ["verification_result", "路径回写"]
      }.freeze

      class << self
        def call(user:, assignment_ref: nil)
          new(user:, assignment_ref:).call
        end
      end

      def initialize(user:, assignment_ref: nil)
        @user = user
        @assignment_ref = assignment_ref.to_s.presence
      end

      def call
        return empty_graph unless session

        projected_nodes = [root_node]
        projected_edges = []
        previous_step_node_id = nil
        steps.each do |step|
          step_node = project_step(step)
          projected_nodes << step_node
          projected_edges << step_edge(step, previous_step_node_id)
          diagnosis_nodes(step).each do |node|
            projected_nodes << node
            projected_edges << {
              "id" => "edge-#{step_node.fetch("id")}-#{node.fetch("id")}",
              "source_node_id" => step_node.fetch("id"),
              "target_node_id" => node.fetch("id"),
              "relation" => "diagnoses",
              "label" => "形成诊断"
            }
          end
          previous_step_node_id = step_node.fetch("id")
        end

        node_ids = projected_nodes.pluck("id")
        stored_current = session.metadata.to_h["current_learning_graph_node_id"]
        current = node_ids.include?(stored_current) ? stored_current : projected_nodes.last.fetch("id")
        {
          "learning_session_id" => session.id.to_s,
          "course_id" => session.course_id&.to_s || session.course_ref,
          "assignment_id" => session.assignment_id&.to_s || session.assignment_ref,
          "current_node_id" => current,
          "nodes" => projected_nodes,
          "edges" => projected_edges,
          "verified_evidence_id" => verified_evidence&.id&.to_s,
          "created_at" => session.started_at.iso8601,
          "writable" => true
        }.compact
      end

      private

      attr_reader :user, :assignment_ref

      def session
        @session ||= begin
          scope = Memury::Session.where(user:).preload(steps: :evidences).order(started_at: :desc)
          if assignment_ref
            scope.detect do |candidate|
              candidate.assignment_ref.to_s == assignment_ref || candidate.assignment_id.to_s == assignment_ref
            end
          else
            scope.first
          end
        end
      end

      def steps
        @steps ||= session.steps.sort_by { |step| [step.sequence, step.id] }
      end

      def empty_graph
        {
          "learning_session_id" => nil,
          "course_id" => nil,
          "assignment_id" => assignment_ref,
          "current_node_id" => nil,
          "nodes" => [],
          "edges" => [],
          "verified_evidence_id" => nil,
          "created_at" => nil,
          "writable" => false
        }
      end

      def root_node
        {
          "id" => root_node_id,
          "kind" => "learning_goal",
          "title" => safe_text(session.objective, 64),
          "summary" => "围绕当前 Assignment 建立的学习目标。",
          "created_at" => session.started_at.iso8601,
          "verification_state" => "exploration",
          "evidence_refs" => [],
          "relationship" => "当前 Assignment 的学习目标",
          "step_id" => nil
        }
      end

      def project_step(step)
        evidences = step.evidences.sort_by(&:id)
        kind, default_title = STEP_KINDS.fetch(step.kind, ["student_question", "学习记录"])
        {
          "id" => step_node_id(step),
          "kind" => kind,
          "title" => step_title(step, default_title),
          "summary" => step_summary(step, evidences),
          "created_at" => step.started_at.iso8601,
          "verification_state" => verification_state(evidences),
          "evidence_refs" => evidences.map { |evidence| evidence_ref(evidence) },
          "relationship" => relationship_for(step),
          "step_id" => step.id.to_s
        }
      end

      def diagnosis_nodes(step)
        step.evidences.select { |evidence| evidence.kind == "diagnosis" }.map do |evidence|
          payload = evidence.payload.to_h.deep_stringify_keys
          {
            "id" => evidence_node_id(evidence),
            "kind" => "diagnosis",
            "title" => misconception_title(payload["misconception_type"]),
            "summary" => safe_text(payload["diagnosis_summary"], 220).presence || "记录了一项待验证的诊断候选。",
            "created_at" => evidence.observed_at.iso8601,
            "verification_state" => "unresolved",
            "evidence_refs" => [evidence_ref(evidence)],
            "relationship" => "由该次作答形成的待验证诊断",
            "step_id" => step.id.to_s
          }
        end
      end

      def step_edge(step, previous_step_node_id)
        parent_step_id = step.input.to_h.deep_stringify_keys["parent_step_id"]
        branch_kind = step.input.to_h.deep_stringify_keys["branch_kind"]
        parent_step = valid_parent_step(step, parent_step_id)
        source = if parent_step
                   step_node_id(parent_step)
                 elsif branch_kind == "root" && parent_step_id.blank?
                   root_node_id
                 else
                   previous_step_node_id || root_node_id
                 end
        relation = step.kind == "student_question" ? "branch" : "sequence"
        {
          "id" => "edge-#{source}-#{step_node_id(step)}",
          "source_node_id" => source,
          "target_node_id" => step_node_id(step),
          "relation" => relation,
          "label" => relation == "branch" ? "从这里继续" : "下一步"
        }
      end

      def valid_parent_step(step, parent_step_id)
        return if parent_step_id.blank?

        candidate = steps.find { |item| item.id.to_s == parent_step_id.to_s }
        return unless candidate

        candidate if [[candidate.sequence, candidate.id], [step.sequence, step.id]].then { |left, right| (left <=> right) == -1 }
      end

      def step_title(step, default_title)
        input = step.input.to_h.deep_stringify_keys
        return safe_text(input["question"], 64) if step.kind == "student_question" && input["question"].present?

        default_title
      end

      def step_summary(step, evidences)
        case step.kind
        when "recall"
          "开始 Recall 基础检查，建立本次学习路径。"
        when "answer"
          "学生已提交一次 Recall 作答；图中不公开不必要的回答原文。"
        when "student_question"
          safe_text(step.input.to_h.deep_stringify_keys["question"], 220)
        when "validation"
          "已完成一次错因核对；普通确认记录仍属于待验证 Evidence。"
        when "hint"
          level = evidences.filter_map { |item| item.payload.to_h["level"] }.max
          "使用#{level ? "第 #{level} 级" : "分层"}提示进行针对性干预。"
        when "practice_generation"
          "已生成并校验迁移任务，尚未代表学生掌握。"
        when "transfer_assessment"
          trusted = evidences.find { |item| effectively_verified?(item) }
          trusted ? "迁移任务已通过可信验证，可进入 Learning Memory。" : "迁移结果尚未形成可信 Evidence。"
        when "replan"
          "学习结果已回到计划层，后续变化仍由既有 Risk Engine 与 Scheduler 决定。"
        else
          "学习路径中的一项探索记录。"
        end
      end

      def verification_state(evidences)
        return "verified" if evidences.any? { |evidence| effectively_verified?(evidence) }
        return "pending" if evidences.any?

        "exploration"
      end

      def evidence_ref(evidence)
        {
          "id" => evidence.id.to_s,
          "kind" => evidence.kind,
          "verified" => effectively_verified?(evidence),
          "observed_at" => evidence.observed_at.iso8601
        }
      end

      def effectively_verified?(evidence)
        payload = evidence.payload.to_h.deep_stringify_keys
        evidence.kind == "transfer_validation" && evidence.verified? && TRUSTED_BASES.include?(payload["validation_basis"])
      end

      def verified_evidence
        session.evidences.sort_by(&:observed_at).reverse.find { |evidence| effectively_verified?(evidence) }
      end

      def relationship_for(step)
        step.kind == "student_question" ? "从历史节点继续的学生分支" : "当前 Session 的第 #{step.sequence} 步"
      end

      def misconception_title(value)
        {
          "conceptual" => "概念边界待确认",
          "procedural" => "解题步骤待确认",
          "calculation" => "计算过程待确认",
          "incomplete" => "论证不完整",
          "guessing" => "依据不足",
          "insufficient_evidence" => "证据不足"
        }.fetch(value.to_s, "待验证误区")
      end

      def safe_text(value, length)
        value.to_s.squish.truncate(length)
      end

      def root_node_id
        "session-#{session.id}"
      end

      def step_node_id(step_or_id)
        id = step_or_id.respond_to?(:id) ? step_or_id.id : step_or_id
        "step-#{id}"
      end

      def evidence_node_id(evidence)
        "evidence-#{evidence.id}"
      end
    end
  end
end
