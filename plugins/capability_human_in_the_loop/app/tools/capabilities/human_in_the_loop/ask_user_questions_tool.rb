# frozen_string_literal: true

module Capabilities
  class HumanInTheLoop
    class AskUserQuestionsTool < RubyLLM::Tool
      QUESTIONS_PARAM_DESCRIPTION = "Array of question objects. Each item must include `prompt` and `options` " \
                                    "(for example `{ prompt: \"What should I look up?\", " \
                                    "options: [\"Customers\", \"Invoices\"] }`), " \
                                    "and may include `label` and `helper_text`."

      description "Ask the user one or more clarification questions in a compact in-chat widget. " \
                  "Each question must include answer options; the widget also lets the user type a custom answer. " \
                  "After calling this tool, wait for the user's next message before continuing. " \
                  "If the user's answers still leave a blocking ambiguity, call this tool again " \
                  "instead of asking a plain-text follow-up question."

      param :prompt,
            desc: "Optional short intro shown above the questions to explain why you need the clarification.",
            type: :string,
            required: false

      param :questions,
            desc: QUESTIONS_PARAM_DESCRIPTION,
            type: :array

      def self.for_agent(agent, chat:, capability:)
        new(agent, chat:, capability:)
      end

      def initialize(agent, chat:, capability:)
        super()
        @agent = agent
        @chat = chat
        @capability = capability
        register_tool_call_tracking
      end

      def name
        Capabilities::HumanInTheLoop::TOOL_RUNTIME_NAME
      end

      def execute(prompt: nil, questions: [])
        return "This tool is only available while chatting with a signed-in user." if @chat&.user.blank?

        state = Capabilities::HumanInTheLoop::ToolCallState.build(
          prompt_text: prompt,
          raw_questions: questions,
          capability: @capability,
        )
        persist_widget_state!(state)

        halt(state.pause_message_content)
      rescue ArgumentError => e
        "Could not ask the user questions: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "[AskUserQuestionsTool] Failed for '#{@agent.name}': #{e.message}"
        "Could not ask the user questions: #{e.message}"
      end

      private

      def register_tool_call_tracking
        return unless @chat.respond_to?(:before_tool_call_execution)

        @chat.before_tool_call_execution do |tool_call|
          next unless tool_call.name.to_s == name

          @current_tool_call_id = tool_call.id
        end
      end

      def persist_widget_state!(state)
        tool_call_record = ToolCall.find_by(tool_call_id: @current_tool_call_id)
        raise "Could not locate the current tool call record." unless tool_call_record

        tool_call_record.update!(
          display_name: Capabilities::HumanInTheLoop::TOOL_DISPLAY_NAME,
          icon: Capabilities::HumanInTheLoop::TOOL_ICON,
          arguments: state.to_h,
        )
      end
    end
  end
end
