# frozen_string_literal: true

module Memury
  class DemoState
    def self.build(now: Time.zone.now)
      assignments = [
        assignment("mech-force", "工程力学基础", "受力分析作业 2", now + 36.hours, 25, 1.0, "平衡力与作用力—反作用力的区别", now),
        assignment("mech-quiz", "工程力学基础", "第 2 章随堂测验", now + 2.days, 20, 0.75, "受力分析", now),
        assignment("code-lab", "程序设计实践", "数组实验报告", now + 4.days, 45, 0.2, "数组与索引", now),
        assignment("code-quiz", "程序设计实践", "循环结构测验", now + 5.days, 20, 0.15, "循环结构", now),
        assignment("mech-review", "工程力学基础", "模拟考试复习清单", now + 6.days, 35, 0.65, "综合受力分析", now)
      ]

      {
        demo_mode: true,
        phase: "overview",
        assignments:,
        concept: {
          name: "平衡力与作用力—反作用力的区别",
          mastery: 0.42,
          confidence: 0.76,
          misconception: "把作用在不同物体上的作用力与反作用力当作平衡力"
        },
        recent_activity_at: (now - 3.days).iso8601,
        completed_assignment_ids: [],
        learning_session: {},
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

    def self.assignment(id, course, title, due_at, minutes, exam_relevance, concept, now)
      {
        id:,
        course_name: course,
        title:,
        due_at: due_at.iso8601,
        submitted: false,
        score: nil,
        estimated_minutes: minutes,
        exam_relevance:,
        concept:,
        source_platform: "Demo Canvas data",
        source_object_id: id,
        source_url: nil,
        last_synced_at: now.iso8601,
        official_or_inferred: "Simulated",
        confidence: 1.0
      }
    end
    private_class_method :assignment

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
