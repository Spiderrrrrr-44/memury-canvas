# frozen_string_literal: true

module Memury
  module Connectors
    class DemoSisConnector < BaseConnector
      def call
        Memury::DemoCourseCatalog.sis_events(now:).map do |event|
          event.merge(provenance("Demo SIS", event[:id], kind: "Simulated"))
        end
      end
    end
  end
end
