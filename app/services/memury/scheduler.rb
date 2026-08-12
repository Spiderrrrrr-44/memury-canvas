# frozen_string_literal: true

module Memury
  class Scheduler
    WORK_WINDOWS = [[9, 12], [14, 18], [19, 22]].freeze
    MAX_BLOCK_MINUTES = 75

    def self.call(user:, assignments:, now: Time.zone.now)
      new(user:, assignments:, now:).call
    end

    def initialize(user:, assignments:, now:)
      @user = user
      @assignments = assignments.map(&:deep_stringify_keys)
      @now = now
    end

    def call
      Memury::PlanBlock.transaction do
        retained = Memury::PlanBlock.where(user:).where("locked = ? OR status = ?", true, "completed").to_a
        Memury::PlanBlock.where(user:, locked: false, status: "planned").delete_all
        occupied = busy_ranges + retained.map { |block| (block.starts_at...block.ends_at) }
        ranked_tasks.each_with_index.flat_map do |task, task_index|
          split_minutes(task.fetch("estimated_minutes", 30).to_i).map.with_index do |minutes, part_index|
            slot = next_slot(minutes, task["due_at"], occupied)
            break [] unless slot

            block = Memury::PlanBlock.create!(
              user:, course_id: existing_id(Course, task["course_id"]), assignment_id: existing_id(Assignment, task["id"]),
              title: block_title(task, part_index), starts_at: slot.begin, ends_at: slot.end,
              reason: scheduling_reason(task, part_index), sequence: (task_index * 10) + part_index,
              metadata: { risk: task["risk"], due_at: task["due_at"], part: part_index + 1 }
            )
            occupied << (block.starts_at...block.ends_at)
            block
          end
        end.flatten
      end
    end

    private

    attr_reader :user, :assignments, :now

    def ranked_tasks
      assignments.reject { |item| item["submitted"] }.sort_by do |item|
        due = parse_time(item["due_at"])
        [-item.fetch("risk", 0).to_f, due]
      end
    end

    def busy_ranges
      Memury::CalendarEvent.where(user:, availability: "busy").where(starts_at: now..(now + 14.days)).map do |event|
        event.starts_at...event.ends_at
      end
    end

    def split_minutes(total)
      total = total.clamp(20, 240)
      Array.new((total.to_f / MAX_BLOCK_MINUTES).ceil) { MAX_BLOCK_MINUTES }.tap do |parts|
        parts[-1] = total - MAX_BLOCK_MINUTES * (parts.length - 1)
      end
    end

    def next_slot(minutes, due_at, occupied)
      deadline = [parse_time(due_at) - 12.hours, now + 14.days].min
      14.times do |day_offset|
        date = (now + day_offset.days).to_date
        WORK_WINDOWS.each do |start_hour, end_hour|
          cursor = Time.zone.local(date.year, date.month, date.day, start_hour)
          cursor = [cursor, aligned_now].max
          window_end = Time.zone.local(date.year, date.month, date.day, end_hour)
          while cursor + minutes.minutes <= window_end && cursor + minutes.minutes <= deadline
            candidate = cursor...(cursor + minutes.minutes)
            return candidate unless occupied.any? { |range| overlap?(candidate, range) }

            cursor += 10.minutes
          end
        end
      end
      nil
    end

    def overlap?(left, right)
      left.begin < right.end && right.begin < left.end
    end

    def block_title(task, part_index)
      suffix = task.fetch("estimated_minutes", 30).to_i > MAX_BLOCK_MINUTES ? " · 第 #{part_index + 1} 段" : ""
      "#{task['course_name']} · #{task['title']}#{suffix}"
    end

    def scheduling_reason(task, part_index)
      reasons = Array(task["risk_reasons"]).first(2)
      reasons << "高权重任务" if task.fetch("points_possible", 0).to_f >= 20
      reasons << "长任务已拆分，保留截止前缓冲" if part_index.positive? || task.fetch("estimated_minutes", 0).to_i > MAX_BLOCK_MINUTES
      reasons.presence&.join("；") || "根据截止时间、风险和可用时间安排"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) || now + 7.days
    rescue ArgumentError, TypeError
      now + 7.days
    end

    def aligned_now
      seconds = (now.min * 60) + now.sec
      offset = (10.minutes - (seconds % 10.minutes)) % 10.minutes
      now.change(sec: 0) + offset
    end

    def existing_id(model, value)
      id = value.to_s.match?(/\A\d+\z/) ? value : nil
      id if id && model.where(id:).exists?
    end
  end
end
