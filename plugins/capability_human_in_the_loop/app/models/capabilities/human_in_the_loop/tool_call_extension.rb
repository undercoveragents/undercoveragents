# frozen_string_literal: true

module Capabilities
  class HumanInTheLoop
    module ToolCallExtension
      PENDING_COMPLETE_MESSAGES = [
        "Waiting for your answers.",
        "Reply in the widget to continue.",
        "The agent is paused for clarification.",
      ].freeze

      ANSWERED_COMPLETE_MESSAGES = [
        "Answers submitted.",
        "Clarification received.",
        "The agent can continue.",
      ].freeze

      def tool_call_widget_render_config
        return unless human_in_the_loop_tool_call?

        {
          view_path: Capabilities::HumanInTheLoop.view_path,
          partial: "human_in_the_loop_tool_calls/tool_call_widget",
          locals: { state: human_in_the_loop_tool_call_state },
        }
      end

      def tool_call_badge_visible?
        !human_in_the_loop_tool_call?
      end

      def tool_call_presentation_override(default_presentation)
        return default_presentation unless human_in_the_loop_tool_call?

        complete_messages = if human_in_the_loop_tool_call_state.pending?
                              PENDING_COMPLETE_MESSAGES
                            else
                              ANSWERED_COMPLETE_MESSAGES
                            end

        default_presentation.with(
          display_name: Capabilities::HumanInTheLoop::TOOL_DISPLAY_NAME,
          icon: Capabilities::HumanInTheLoop::TOOL_ICON,
          complete_messages:,
        )
      end

      def human_in_the_loop_tool_call?
        name == Capabilities::HumanInTheLoop::TOOL_RUNTIME_NAME && human_in_the_loop_tool_call_state.renderable?
      end

      def human_in_the_loop_tool_call_state
        Capabilities::HumanInTheLoop::ToolCallState.from_arguments(arguments)
      end

      def human_in_the_loop_resume_message_content
        human_in_the_loop_tool_call_state.resume_message_content
      end

      def arguments_for_llm
        return arguments unless human_in_the_loop_tool_call?

        human_in_the_loop_tool_call_state.to_h.slice("prompt", "questions")
      end
    end
  end
end
