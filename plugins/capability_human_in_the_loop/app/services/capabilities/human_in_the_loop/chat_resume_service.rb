# frozen_string_literal: true

module Capabilities
  class HumanInTheLoop
    class ChatResumeService
      def initialize(tool_call)
        @tool_call = tool_call
      end

      def call
        @tool_call.message.chat.enqueue_response!(content: @tool_call.human_in_the_loop_resume_message_content)
      end
    end
  end
end
