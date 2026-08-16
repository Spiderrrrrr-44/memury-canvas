# frozen_string_literal: true

require_relative "open_ai_provider"

module Memury
  module Teaching
    module ProviderRegistry
      module_function

      def current
        OpenAiProvider.new
      end
    end
  end
end
