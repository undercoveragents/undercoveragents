# frozen_string_literal: true

module Capabilities
  class Memory
    # Concern mixed into Agent at boot (via plugin.rb reloader.to_prepare)
    # to add memory-related associations and convenience methods.
    module AgentExtension
      extend ActiveSupport::Concern

      included do
        has_many :agent_memory_blocks, dependent: :destroy
        has_many :archival_memories, dependent: :destroy

        # Amoeba: archival memories are NOT cloned (fresh start per version).
        amoeba do
          exclude_association :archival_memories
          exclude_association :agent_memory_blocks
        end
      end

      # Returns the AgentMemoryBlock for +label+ scoped to +user+, or nil.
      def agent_memory_block_for(label:, user:)
        agent_memory_blocks.where(user:).joins(:memory_block).find_by(memory_blocks: { label: })
      end

      # Returns all AgentMemoryBlock rows for +user+ (eager-loaded with memory_block).
      def user_memory_blocks(user)
        agent_memory_blocks.where(user:).includes(:memory_block)
      end

      # Returns true if +user+ has at least one memory block bootstrapped for this agent.
      def memory_configured_for?(user)
        agent_memory_blocks.exists?(user:)
      end

      # Attaches an existing MemoryBlock template to this agent for a specific user.
      # Creates an AgentMemoryBlock row with the template's default_value. Idempotent.
      def attach_memory_block_for_user(block, user:)
        agent_memory_blocks.find_or_create_by!(memory_block: block, user:) do |amb|
          amb.value = block.default_value
        end
      end

      # Detaches a user's AgentMemoryBlock for the given MemoryBlock template.
      def detach_memory_block_for_user(block, user:)
        agent_memory_blocks.find_by(memory_block: block, user:)&.destroy
      end

      # Returns true if ANY user has memory blocks configured for this agent.
      # Used to determine if the agent has memory capability set up at all.
      def memory_configured?
        agent_memory_blocks.exists?
      end
    end
  end
end
