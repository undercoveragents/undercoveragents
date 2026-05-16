# frozen_string_literal: true

module Capabilities
  class Memory
    # Seeds an agent with standard memory blocks.
    #
    # Usage — minimal (just default blocks):
    #   Bootstrapper.new(agent).bootstrap!
    #
    # Usage — with initial values:
    #   Bootstrapper.new(agent,
    #     persona: "I am a formal technical assistant.",
    #     human: "User prefers concise answers.",
    #   ).bootstrap!
    #
    # Usage — attach shared read-only blocks:
    #   Bootstrapper.new(agent, shared_block_ids: [policy_block.id]).bootstrap!
    class Bootstrapper
      DEFAULT_BLOCKS = [
        {
          label: "persona",
          description: "Stores details about the agent's current persona, " \
                       "guiding how it behaves and responds. The agent can update this.",
          char_limit: 5000,
        },
        {
          label: "human",
          description: "Stores key details about the person this agent is conversing with, " \
                       "allowing for personalized responses. The agent can update this.",
          char_limit: 5000,
        },
      ].freeze

      def initialize(agent, user:, persona: nil, human: nil, shared_block_ids: [])
        @agent = agent
        @user = user
        @initial_values = { "persona" => persona, "human" => human }.compact
        @shared_block_ids = shared_block_ids
      end

      # Creates global MemoryBlock templates if missing, then attaches user-scoped
      # AgentMemoryBlock rows seeded from initial values or template defaults.
      # Idempotent — skips blocks the user already has for this agent.
      #
      # @return [ActiveRecord::Relation] all AgentMemoryBlock rows for this user+agent
      def bootstrap!
        ActiveRecord::Base.transaction do
          create_default_blocks!
          attach_shared_blocks!
        end

        @agent.user_memory_blocks(@user).reload
      end

      private

      def create_default_blocks!
        DEFAULT_BLOCKS.each do |config|
          # Find or create the global template (label is the natural key).
          block = MemoryBlock.find_or_create_by!(label: config[:label]) do |b|
            b.description = config[:description]
            b.char_limit = config[:char_limit]
            b.default_value = @initial_values[config[:label]] || ""
          end

          # Seed the user-specific row (idempotent — skips if already exists).
          initial_value = @initial_values[config[:label]] || block.default_value
          AgentMemoryBlock.find_or_create_by!(agent: @agent, memory_block: block, user: @user) do |amb|
            amb.value = initial_value
          end
        end
      end

      def attach_shared_blocks!
        return if @shared_block_ids.empty?

        MemoryBlock.where(id: @shared_block_ids).find_each do |block|
          AgentMemoryBlock.find_or_create_by!(agent: @agent, memory_block: block, user: @user) do |amb|
            amb.value = block.default_value
          end
        end
      end
    end
  end
end
