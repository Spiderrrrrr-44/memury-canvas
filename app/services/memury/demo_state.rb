# frozen_string_literal: true

module Memury
  class DemoState
    def self.build(now: Time.zone.now)
      assignments = Memury::DemoCourseCatalog.assignments(now:)

      {
        demo_mode: true,
        phase: "overview",
        assignments:,
        demo_course_catalog: Memury::DemoCourseCatalog.courses,
        concept: {
          name: "平衡力与作用力—反作用力的区别",
          mastery: 0.42,
          confidence: 0.76,
          misconception: "把作用在不同物体上的作用力与反作用力当作平衡力",
          reference_answer: "桌面对书的支持力与书对桌面的压力作用在不同物体上，不是一对平衡力。"
        },
        recent_activity_at: (now - 3.days).iso8601,
        completed_assignment_ids: [],
        learning_session: {
          recall_question: "一本书静止在桌面上。桌面对书的支持力与书对桌面的压力是一对平衡力吗？"
        },
        sis_events: Memury::Connectors::DemoSisConnector.new(user: nil, now:).call,
        evidence: [
          { title: "受力分析作业 1：相关题目作答错误", source: "Demo learning evidence", observed_at: (now - 2.days).iso8601 }
        ],
        study_blocks: blocks(now),
        decision_logs: [],
        last_synced_at: now.iso8601
      }
    end

    def self.blocks(now)
      [
        block("recall", "Recall：回忆关键区别", 10, now + 18.hours),
        block("repair", "Repair：诊断并修复错因", 15, now + 18.hours + 10.minutes),
        block("transfer", "Transfer：完成跨情境迁移", 10, now + 18.hours + 25.minutes)
      ]
    end

    def self.block(stage, title, minutes, starts_at)
      {
        id: "block-#{stage}",
        stage:,
        title:,
        starts_at: starts_at.iso8601,
        duration_minutes: minutes,
        status: "planned",
        course_name: "工程力学基础",
        concept: "平衡力与作用力—反作用力的区别",
        official_or_inferred: "Inferred",
        source_platform: "Memury",
        source_object_id: "block-#{stage}",
        last_synced_at: starts_at.iso8601,
        confidence: 0.86
      }
    end
    private_class_method :block
  end
end
