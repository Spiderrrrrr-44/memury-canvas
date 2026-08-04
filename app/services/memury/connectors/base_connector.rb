# frozen_string_literal: true

module Memury
  module Connectors
    class BaseConnector
      def initialize(user:, now: Time.zone.now)
        @user = user
        @now = now
      end

      private

      attr_reader :user, :now

      def provenance(platform, id, url: nil, kind: "Official", confidence: 1.0)
        { source_platform: platform, source_object_id: id.to_s, source_url: url,
          last_synced_at: now.iso8601, official_or_inferred: kind, confidence: }
      end
    end
  end
end
