# frozen_string_literal: true

module Memury
  class LearnerStateUpdater
    def self.call(current_mastery:,
                  diagnostic_correct:,
                  used_hint:,
                  hypothesis_verified:,
                  transfer_correct:,
                  validated: true,
                  current_confidence: nil)
      unless validated
        current = current_mastery.to_f.round(2)
        return {
          mastery: current,
          previous_mastery: current,
          delta: 0.0,
          confidence: current_confidence.nil? ? 0.0 : current_confidence.to_f.round(2),
          reason: "验证未完成，未更新 Learner State"
        }
      end

      delta = diagnostic_correct ? 0.08 : -0.06
      delta += 0.05 if hypothesis_verified
      delta += if transfer_correct
                 used_hint ? 0.12 : 0.24
               else
                 -0.04
               end
      mastery = (current_mastery.to_f + delta).clamp(0.0, 1.0).round(2)
      {
        mastery:,
        previous_mastery: current_mastery.to_f.round(2),
        delta: delta.round(2),
        confidence: hypothesis_verified ? 0.86 : 0.62,
        reason: (transfer_correct && !used_hint) ? "无关键提示完成迁移题，形成强掌握证据" : "根据诊断、验证题和提示使用情况更新"
      }
    end
  end
end
