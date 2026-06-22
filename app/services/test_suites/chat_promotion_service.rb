# frozen_string_literal: true

module TestSuites
  class ChatPromotionService
    Result = Data.define(:test_suite, :test_case, :created) do
      def created?
        created
      end
    end

    SUITE_SOURCE = "inspector_chat_promotions"
    TEST_CASE_SOURCE_TYPE = "chat"

    def self.call(chat:, assistant_message:, user:)
      new(chat:, assistant_message:, user:).call
    end

    def initialize(chat:, assistant_message:, user:)
      @chat = chat
      @assistant_message = assistant_message
      @user = user
    end

    def call
      validate!

      ApplicationRecord.transaction do
        test_suite = promotion_suite
        test_case = promoted_test_case(test_suite)
        created = test_case.new_record?

        test_case.assign_attributes(test_case_attributes(test_case))
        test_case.save!

        Result.new(test_suite:, test_case:, created:)
      end
    end

    private

    attr_reader :chat, :assistant_message, :user

    def validate!
      raise ArgumentError, "Only chats backed by an agent can be promoted." if agent.blank?
      raise ArgumentError, "Only assistant messages can be promoted." unless assistant_message&.assistant?
      raise ArgumentError, "Message does not belong to this chat." unless assistant_message.chat_id == chat.id
      raise ArgumentError, "Promoted assistant messages need a preceding user prompt." if prompt_message.blank?
      raise ArgumentError, "Promoted test cases need an expected answer." if expected_answer.blank?
    end

    def agent
      chat.agent
    end

    def promotion_suite
      @promotion_suite ||= promotion_suite_scope.first_or_create! do |suite|
        suite.name = "Production examples - #{agent.name}"
        suite.description = "Chat examples promoted from the inspector for repeatable evaluation."
        suite.source_metadata = {
          "source" => SUITE_SOURCE,
          "agent_id" => agent.id,
        }
      end
    end

    def promotion_suite_scope
      TestSuite
        .where(agent:, suite_type: "agent", source_type: "manual")
        .where("source_metadata ->> 'source' = ?", SUITE_SOURCE)
    end

    def promoted_test_case(test_suite)
      test_suite.test_cases.find_or_initialize_by(scenario_key:)
    end

    def scenario_key
      "chat-#{chat.id}-message-#{assistant_message.id}"
    end

    def test_case_attributes(test_case)
      {
        name: test_case_name,
        prompt: prompt_text,
        expected_answer: expected_answer.truncate(10_000, omission: ""),
        match_type: "semantic",
        position: test_case.new_record? ? next_position(test_case.test_suite) : test_case.position,
        category: "production",
        source_type: TEST_CASE_SOURCE_TYPE,
        source_metadata:,
      }
    end

    def test_case_name
      "Chat ##{chat.id}: #{prompt_text.truncate(120, omission: "")}".truncate(200, omission: "")
    end

    def prompt_text
      @prompt_text ||= prompt_message.display_content.to_s.truncate(5000, omission: "")
    end

    def expected_answer
      @expected_answer ||= if latest_feedback&.negative? && latest_feedback.comment.present?
                             latest_feedback.comment.to_s
                           else
                             assistant_message.display_content.to_s
                           end
    end

    def prompt_message
      @prompt_message ||= prompt_message_scope.first
    end

    def prompt_message_scope
      chat.messages
          .user
          .where(created_at: ..assistant_message.created_at)
          .order(created_at: :desc, id: :desc)
    end

    def latest_feedback
      @latest_feedback ||= assistant_message.message_feedbacks.order(created_at: :desc, id: :desc).first
    end

    def next_position(test_suite)
      test_suite.test_cases.maximum(:position).to_i + 1
    end

    def source_metadata
      {
        "source" => TEST_CASE_SOURCE_TYPE,
        "chat_id" => chat.id,
        "chat_title" => chat.display_title,
        "chat_execution_context" => chat.execution_context,
        "agent_id" => agent.id,
        "prompt_message_id" => prompt_message.id,
        "assistant_message_id" => assistant_message.id,
        "promoted_by_user_id" => user.id,
        "promoted_at" => Time.current.iso8601,
        "feedback" => feedback_metadata,
      }
    end

    def feedback_metadata
      {
        "id" => latest_feedback&.id,
        "value" => latest_feedback&.value,
        "category" => latest_feedback&.category,
        "comment" => latest_feedback&.comment,
      }.compact
    end
  end
end
