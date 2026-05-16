# frozen_string_literal: true

module Capabilities
  class Memory
    # Replaces the entire content of a named core memory block.
    # Use when you want to completely rewrite what's in a block.
    class MemoryReplaceTool < RubyLLM::Tool
      description "Replace the entire content of a core memory block. " \
                  "Use when you want to fully rewrite a block's content. " \
                  "For appending, use memory_insert instead."

      param :block_label,
            desc: "The label of the memory block to update (e.g. 'human', 'persona')",
            type: :string

      param :new_value,
            desc: "The new content to set. Completely replaces current content.",
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
        "memory_replace"
      end

      def execute(block_label:, new_value:)
        amb = @agent.agent_memory_block_for(label: block_label, user: @user)

        return error_result("Block '#{block_label}' not found") unless amb
        return error_result("Block '#{block_label}' is read-only") if amb.read_only?

        if new_value.length > amb.char_limit
          return error_result(
            "Content (#{new_value.length} chars) exceeds limit of #{amb.char_limit} chars. " \
            "Shorten your content or use memory_insert for incremental updates.",
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
