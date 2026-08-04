# frozen_string_literal: true

module Memury
  class DemoState
    def self.build(now: Time.zone.now)
      due = now + 36.hours
      assignments = [
        ["mech-force", "工程力学基础", "受力分析作业 2", due, 0.42],
        ["mech-quiz", "工程力学基础", "第 2 章随堂测验", now + 2.days, 0.58],
        ["code-lab", "程序设计实践", "数组实验报告", now + 4.days, 0.31],
        ["code-quiz", "程序设计实践", "循环结构测验", now + 5.days, 0.22],
        ["mech-review", "工程力学基础", "模拟考试复习清单", now + 6.days, 0.49]
      ].map do |id, course, title, deadline, risk|
        { id:, course_name: course, title:, due_at: deadline.iso8601, risk:, source_platform: "Canvas Demo Seed",
          source_object_id: id, source_url: nil, last_synced_at: now.iso8601, official_or_inferred: "Official", confidence: 1.0 }
      end
      {
        demo_mode: true, phase: "overview", assignments:,
        concept: { name: "平衡力与作用力—反作用力的区别", mastery: 0.42, confidence: 0.76,
                   misconception: "把作用在不同物体上的作用力与反作用力当作平衡力" },
        evidence: [{ title: "受力分析作业 1：相关题目作答错误", source: "Canvas Demo Seed", observed_at: (now - 2.days).iso8601 }],
        study_blocks: blocks(now), decision_logs: [], last_synced_at: now.iso8601
      }
    end

    def self.blocks(now)
      [["概念诊断", 25, 18], ["完成受力分析作业", 50, 25], ["无提示检查与迁移", 20, 27]].map.with_index do |(title, minutes, hours), index|
        { id: "block-#{index + 1}", title:, starts_at: (now + hours.hours).iso8601, duration_minutes: minutes,
          status: "planned", course_name: "工程力学基础", concept: "平衡力与作用力—反作用力的区别",
          official_or_inferred: "Inferred", source_platform: "Memury", source_object_id: "block-#{index + 1}",
          last_synced_at: now.iso8601, confidence: 0.82 }
      end
    end
  end
end
