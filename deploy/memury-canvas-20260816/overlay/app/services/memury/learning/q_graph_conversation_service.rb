# frozen_string_literal: true

require_relative "../ai/structured_response_client"
require_relative "../ai/teaching_capability_schemas"

module Memury
  module Learning
    class QGraphConversationService
      MAX_TURNS = 12

      def initialize(client: Memury::Ai::StructuredResponseClient.new)
        @client = client
      end

      def reply(document_title:, document_excerpt:, question:, conversation:, locale:)
        result = client.call(
          capability: "q_graph_reply",
          instructions: instructions(locale),
          input: {
            "locale" => normalized_locale(locale),
            "document" => {
              "title" => clean(document_title, 160),
              "excerpt" => clean(document_excerpt, 1_200)
            },
            "conversation" => sanitized_conversation(conversation),
            "question" => clean(question, 240)
          },
          schema: Memury::Ai::TeachingCapabilitySchemas::Q_GRAPH_REPLY,
          schema_version: Memury::Ai::TeachingCapabilitySchemas::VERSION,
          max_output_tokens: 900
        )
        result.data.merge(
          "source" => "openai",
          "provider_metadata" => result.metadata
        )
      rescue Memury::Ai::StructuredResponseClient::Error => e
        deterministic_reply(
          document_title:,
          document_excerpt:,
          question:,
          conversation:,
          locale:,
          fallback_reason: e.category
        )
      end

      private

      attr_reader :client

      def instructions(locale)
        <<~TEXT
          You are Q Graph, a document-grounded learning conversation partner.
          Reply in #{normalized_locale(locale)}. Use only the supplied document
          excerpt and prior conversation. Be warm, concise and conversational.
          Explain ideas directly, ask one useful follow-up, and never claim that
          a learner has mastered something. Do not reveal private reasoning.
          The conversation_summary must summarize the entire conversation so
          far, not only the latest turn. Return only the requested JSON.
        TEXT
      end

      def sanitized_conversation(conversation)
        Array(conversation).last(MAX_TURNS).filter_map do |message|
          role = message.to_h["role"].to_s
          next unless %w[user assistant].include?(role)

          { "role" => role, "content" => clean(message.to_h["content"], 700) }
        end
      end

      def deterministic_reply(document_title:, document_excerpt:, question:, conversation:, locale:, fallback_reason:)
        chinese = normalized_locale(locale) == "zh-CN"
        title = clean(document_title, 100).presence || (chinese ? "当前文档" : "this document")
        excerpt = clean(document_excerpt, 260).presence
        prompt = clean(question, 180)
        prior_questions = sanitized_conversation(conversation)
          .select { |item| item["role"] == "user" }
          .last(3)
          .pluck("content")
        questions = (prior_questions + [prompt]).compact_blank.uniq

        if chinese
          answer = "我们继续围绕《#{title}》来看。你问的是“#{prompt}”。"
          answer += " 文档里最相关的依据是：#{excerpt}" if excerpt
          answer += " 可以先把它拆成“对象、条件、结论”三部分，再检查结论是否仍然成立。"
          follow_up = "你想先核对文档中的原句，还是用一个新例子继续推演？"
          summary = "本次对话围绕《#{title}》展开，重点讨论了：#{questions.join("；")}。"
          points = ["回到文档原文确认依据", "区分对象、条件与结论", "用新情境检验理解"]
        else
          answer = "Let’s keep this anchored in “#{title}.” You asked: “#{prompt}.”"
          answer += " The most relevant passage is: #{excerpt}" if excerpt
          answer += " A useful next move is to separate the object, condition, and conclusion, then test whether the conclusion still holds."
          follow_up = "Would you like to inspect the exact passage first, or test the idea with a new example?"
          summary = "This conversation used “#{title}” to explore: #{questions.join("; ")}."
          points = ["Ground claims in the document", "Separate object, condition, and conclusion", "Test understanding in a new context"]
        end

        {
          "answer" => answer.truncate(700),
          "follow_up" => follow_up,
          "conversation_summary" => summary.truncate(500),
          "key_points" => points,
          "source" => "deterministic_fallback",
          "provider_metadata" => { "fallback_reason" => fallback_reason }
        }
      end

      def clean(value, length)
        value.to_s.squish.truncate(length)
      end

      def normalized_locale(value)
        value.to_s.downcase.start_with?("zh") ? "zh-CN" : "en"
      end
    end
  end
end
