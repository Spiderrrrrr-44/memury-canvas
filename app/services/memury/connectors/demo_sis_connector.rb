# frozen_string_literal: true

module Memury
  module Connectors
    class DemoSisConnector < BaseConnector
      def call
        base = now.beginning_of_day
        [
          { id: "sis-mech-class", title: "工程力学基础（模拟 SIS 上课）", starts_at: (base + 1.day + 9.hours).iso8601, location: "工科楼 B201" },
          { id: "sis-cs-class", title: "程序设计实践（模拟 SIS 上课）", starts_at: (base + 2.days + 14.hours).iso8601, location: "机房 A305" },
          { id: "sis-mech-exam", title: "工程力学基础模拟考试", starts_at: (base + 3.days + 9.hours).iso8601, location: "教学楼 101", exam: true }
        ].map { |event| event.merge(provenance("Demo SIS", event[:id])) }
      end
    end
  end
end
