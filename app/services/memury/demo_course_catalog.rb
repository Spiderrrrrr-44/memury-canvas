# frozen_string_literal: true

module Memury
  class DemoCourseCatalog
    COURSES = [
      { id: "ME250", name: "ME 250: Engineering Dynamics", instructor: "Prof. Laura Chen", credits: 4, schedule: "周一/三/五 10:00–10:50", room: "DCL 1320", progress: "Week 8 · Rigid Body Kinetics" },
      { id: "TAM212", name: "TAM 212: Introductory Dynamics", instructor: "Prof. Ethan Miller", credits: 3, schedule: "周二/四 09:30–10:50", room: "MEB 253", progress: "Week 8 · Work and Energy" },
      { id: "MATH257", name: "MATH 257: Linear Algebra", instructor: "Prof. Sophia Wang", credits: 3, schedule: "周一/三/五 13:00–13:50", room: "Altgeld 314", progress: "Week 8 · Eigenvalues" },
      { id: "CS101", name: "CS 101: Intro Computing", instructor: "Prof. Daniel Kim", credits: 3, schedule: "周二/四 13:00–14:20", room: "CIF 0035", progress: "Week 8 · NumPy and Data Analysis" },
      { id: "PHYS212", name: "PHYS 212: Electricity & Magnetism", instructor: "Prof. Rachel Davis", credits: 4, schedule: "周一/三 15:00–16:20", room: "Loomis 141", progress: "Week 8 · Electric Potential" },
      { id: "RHET105", name: "RHET 105: Academic Writing", instructor: "Dr. Maya Patel", credits: 4, schedule: "周二/四 11:00–12:20", room: "English Building 104", progress: "Week 8 · Evidence-based Argument" }
    ].freeze

    TASKS = [
      ["ME250-HW3", "ME250", "Homework 3: Particle Kinetics", "作业", -260, 180, 4, "已评分 · 68/100", true, 68, "Particle kinetics"],
      ["ME250-HW4", "ME250", "Homework 4: Work and Energy", "作业", 32, 200, 5, "进行中 · 3/7", false, nil, "Work and energy"],
      ["ME250-Q2", "ME250", "Quiz 2: Force Analysis", "Quiz", 43, 35, 6, "未开始", false, nil, "Force analysis"],
      ["ME250-MID", "ME250", "Midterm Exam", "考试", -310, 90, 18, "已评分 · 74/100", true, 74, "Particle kinetics"],
      ["TAM212-HW6", "TAM212", "Homework 6: Work–Energy", "作业", 55, 150, 4, "未开始", false, nil, "Work–energy"],
      ["TAM212-LAB2", "TAM212", "Motion Tracking Lab", "实验报告", 130, 240, 8, "草稿已保存", false, nil, "Motion tracking"],
      ["TAM212-Q4", "TAM212", "Quiz 4: Momentum", "Quiz", 66, 25, 3, "未开始", false, nil, "Momentum and collision"],
      ["MATH257-PS5", "MATH257", "Problem Set 5", "作业", -38, 160, 4, "迟交 · 82/100", true, 82, "Orthogonal projection"],
      ["MATH257-PS6", "MATH257", "Problem Set 6: Eigenvalues", "作业", 154, 180, 4, "未开始", false, nil, "Eigenvalues"],
      ["MATH257-Q3", "MATH257", "Quiz 3: Least Squares", "Quiz", -50, 20, 3, "已评分 · 55/100", true, 55, "Least squares"],
      ["CS101-MP3", "CS101", "Machine Problem 3", "编程作业", 81, 300, 8, "已完成约 40%", false, nil, "NumPy vectorization"],
      ["CS101-LAB7", "CS101", "Lab 7: NumPy Arrays", "实验", 27, 60, 2, "未开始", false, nil, "NumPy arrays"],
      ["CS101-Q5", "CS101", "Weekly Quiz 5", "Quiz", 57, 20, 2, "未开始", false, nil, "Broadcasting"],
      ["PHYS212-HW7", "PHYS212", "Homework 7: Electric Potential", "作业", 32, 140, 3, "已完成 · 9/12", false, nil, "Electric potential"],
      ["PHYS212-PQ6", "PHYS212", "Prelecture Quiz 6", "Quiz", 22, 20, 1, "未开始", false, nil, "Potential and field"],
      ["PHYS212-EX2", "PHYS212", "Exam 2", "考试", -280, 90, 20, "已评分 · 79/100", true, 79, "Gauss's law"],
      ["RHET105-D2", "RHET105", "Essay 2 Draft", "论文草稿", -64, 300, 5, "已提交 · 待反馈", true, nil, "Evidence-based argument"],
      ["RHET105-E2", "RHET105", "Essay 2 Final", "论文", 202, 360, 15, "未开始", false, nil, "Evidence–claim linkage"],
      ["RHET105-PR2", "RHET105", "Peer Review 2", "同伴互评", 75, 80, 3, "0/2 完成", false, nil, "Peer review" ]
    ].freeze

    EVIDENCE = [
      ["EV-001", "ME250-HW3", "斜面滑块受力分析", "摩擦方向判断", "建模前没有明确系统边界", 0.94, true],
      ["EV-002", "ME250-HW3", "曲线运动加速度", "n-t 坐标系", "过早套公式，遗漏适用条件", 0.93, true],
      ["EV-003", "ME250-HW3", "绳约束系统", "运动约束", "约束关系缺少符号检查", 0.82, true],
      ["EV-004", "ME250-MID", "系统边界与受力图", "系统边界与受力图", "建模前没有明确系统边界", 0.91, true],
      ["EV-005", "ME250-MID", "功能原理初始状态", "功能原理", "过早套公式，遗漏适用条件", 0.84, true],
      ["EV-006", "MATH257-Q3", "正交投影", "正交投影", "矩阵运算次序不稳定", 0.82, true],
      ["EV-007", "MATH257-Q3", "最小二乘正规方程", "最小二乘", "矩阵运算次序不稳定", 0.89, true],
      ["EV-008", "CS101-MP3", "数组处理性能", "NumPy 向量化", "能得到结果，但缺乏向量化思维", 0.86, true],
      ["EV-009", "PHYS212-EX2", "高斯定律适用条件", "高斯定律", "过早套公式，遗漏适用条件", 0.91, true],
      ["EV-010", "RHET105-D2", "论证结构", "Evidence–claim linkage", "引用证据后缺少解释", 0.46, false]
    ].freeze

    def self.courses
      COURSES.map(&:stringify_keys)
    end

    def self.assignments(now: Time.zone.now)
      TASKS.map do |id, course_id, title, type, due_hours, duration, weight, status, submitted, score, concept|
        course = COURSES.find { |item| item[:id] == course_id }
        {
          id:, course_id:, course_name: course[:name], title:, task_type: type,
          due_at: (now + due_hours.hours).iso8601, submitted:, score:,
          points_possible: 100, estimated_minutes: duration, weight_percent: weight,
          progress_label: status, concept:, exam_relevance: type == "考试" ? 1.0 : 0.25,
          source_platform: "Demo Canvas data", source_object_id: id, source_url: nil,
          last_synced_at: now.iso8601, official_or_inferred: "Simulated", confidence: 1.0
        }
      end
    end

    def self.evidence
      EVIDENCE.map do |id, assignment_id, title, concept, pattern, confidence, verified|
        {
          id:, assignment_id:, kind: title.include?("论证") ? "teacher_feedback" : "item_error",
          title:, summary: evidence_summary(id), concept:, error_pattern: pattern,
          verified:, confidence:, source_kind: "demo", source_ref: id
        }
      end
    end

    def self.sis_events(now: Time.zone.now)
      COURSES.map.with_index do |course, index|
        { id: "SIS-#{course[:id]}", title: "#{course[:name]} · #{course[:schedule]}",
          starts_at: (now.beginning_of_day + (index + 1).days + 9.hours).iso8601,
          location: course[:room], course_id: course[:id] }
      end + [
        { id: "SIS-ME250-Q2", title: "ME 250 Quiz 2", starts_at: (now + 43.hours).iso8601, location: "DCL 1320", exam: true },
        { id: "SIS-PHYS212-REVIEW", title: "PHYS 212 Exam Review", starts_at: (now + 4.days).iso8601, location: "Loomis 141", exam: true }
      ]
    end

    def self.calendar_events(now: Time.zone.now)
      course_events = COURSES.map.with_index do |course, index|
        start = now.beginning_of_day + (index + 1).days + [10, 9, 13, 13, 15, 11][index].hours
        { id: "CAL-0#{index + 1}", title: "#{course[:id]} · #{course[:schedule]}", starts_at: start,
          ends_at: start + [50, 80, 50, 80, 80, 80][index].minutes, source_kind: "course",
          availability: "busy", recurrence_rule: "FREQ=WEEKLY", locked: true, course_id: course[:id] }
      end
      course_events + [
        calendar("CAL-07", "健身", now.change(hour: 19), 120, "busy"),
        calendar("CAL-08", "机器人组会", now.advance(days: 1).change(hour: 14), 60, "busy"),
        calendar("CAL-09", "晚餐与休息", now.advance(days: 2).change(hour: 18, min: 30), 60, "flexible"),
        calendar("CAL-10", "外出拍照", now.advance(days: 4).change(hour: 13, min: 30), 240, "busy")
      ]
    end

    def self.focus_records(now: Time.zone.now)
      [[5, "ME250-HW4", 47], [4, "MATH257-Q3", 32], [3, "CS101-MP3", 71], [2, "RHET105-D2", 108], [1, "ME250-HW4", 64]].map do |days, assignment_id, minutes|
        { id: "FOCUS-#{6 - days}", assignment_id:, started_at: now - days.days, minutes: }
      end
    end

    def self.questions(now: Time.zone.now)
      [
        ["如何在运动方向未知时判断静摩擦力方向？", "ME250-HW3", "open", 1],
        ["什么时候必须使用法向加速度 v²/ρ？", "ME250-HW3", "investigating", 2],
        ["高斯定律成立与可以直接求出电场有什么区别？", "PHYS212-EX2", "open", 1],
        ["为什么最小二乘解要乘 Aᵀ？", "MATH257-Q3", "open", 4],
        ["Broadcasting 的两个数组维度如何匹配？", "CS101-MP3", "resolved", 7],
        ["引用后怎样解释证据与中心论点的关系？", "RHET105-D2", "investigating", 8]
      ].map do |content, assignment_id, status, review_days|
        { content:, assignment_id:, status:, review_at: now + review_days.days }
      end
    end

    def self.calendar(id, title, starts_at, minutes, availability)
      { id:, title:, starts_at:, ends_at: starts_at + minutes.minutes, source_kind: "personal",
        availability:, recurrence_rule: nil, locked: availability == "busy" }
    end
    private_class_method :calendar

    def self.evidence_summary(id)
      {
        "EV-001" => "先判断相对滑动趋势，再确定摩擦方向。",
        "EV-002" => "加速度同时包含切向与法向分量。",
        "EV-003" => "应先写绳长不变关系，再求导。",
        "EV-004" => "系统级受力图中不应保留内力。",
        "EV-005" => "必须同时评估初态与末态能量。",
        "EV-006" => "应检查残差是否与列空间正交。",
        "EV-007" => "正规方程为 AᵀAx=Aᵀb。",
        "EV-008" => "应使用布尔索引与数组运算。",
        "EV-009" => "直接用 EA=q/ε₀ 需要对称性。",
        "EV-010" => "引用后需要解释证据如何支持中心论点。"
      }.fetch(id)
    end
    private_class_method :evidence_summary
  end
end
