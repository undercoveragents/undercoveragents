# frozen_string_literal: true

module Capabilities
  class Memory
    # Assembles memory blocks XML for injection into the LLM system prompt.
    #
    # Pure service — no side effects, easy to test.
    #
    # Usage:
    #   xml = ContextBuilder.new(agent, user:).build
    #   # => "<memory_blocks>\n<human>...</human>\n<persona>...</persona>\n</memory_blocks>"
    #   # => nil if no memory blocks are bootstrapped for this user
    class ContextBuilder
      def initialize(agent, user:)
        @agent = agent
        @user  = user
      end

      # @return [String, nil] memory blocks XML envelope, or nil if no blocks for this user
      def build
        return nil unless @user
        return nil unless user_blocks.any?

        blocks_xml = user_blocks.map(&:render_xml).join("\n\n")

        <<~XML.strip
          <memory_blocks>

          #{blocks_xml}

          </memory_blocks>
        XML
      end

      private

      # Eager-load memory_block template to avoid N+1.
      def user_blocks
        @user_blocks ||= @agent.user_memory_blocks(@user).load
      end
    end
  end
end
