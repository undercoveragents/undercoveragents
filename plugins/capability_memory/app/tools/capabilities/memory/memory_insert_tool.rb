# frozen_string_literal: true

module Capabilities
  class Memory
    # Appends text to an existing core memory block without erasing current content.
    # Use when you want to ADD information rather than replace everything.
    class MemoryInsertTool < RubyLLM::Tool
      description "Append text to a core memory block, preserving existing content. " \
                  "Use when you want to ADD new information to a block. " \
                  "For full replacement, use memory_replace instead."

      param :block_label,
            desc: "The label of the memory block to append to (e.g. 'human', 'persona')",
            type: :string

      param :text,
            desc: "The text to append. Will be added on a new line after existing content.",
            type: :string

      def self.for_agent(agent, user:)
        new(agent, user)
      end

      def initialize(agent, user)
        super()
        @agent = agent
        @user  = user
      end

      def name
        "memory_insert"
      end

      def execute(block_label:, text:)
        amb = @agent.agent_memory_block_for(label: block_label, user: @user)

        return error_result("Block '#{block_label}' not found") unless amb
        return error_result("Block '#{block_label}' is read-only") if amb.read_only?

        new_value = [amb.value.presence, text.strip].compact.join("\n")

        if new_value.length > amb.char_limit
          return error_result(
            "Appending would result in #{new_value.length} chars, exceeding limit of #{amb.char_limit}. " \
            "Consider using memory_replace to rewrite the block more concisely first.",
          )
        end

        amb.update!(value: new_value)

        {
          success: true,
          block_label:,
          chars_used: new_value.length,
          chars_remaining: amb.chars_remaining,
          chars_limit: amb.char_limit,
        }
      end

      private

      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end
