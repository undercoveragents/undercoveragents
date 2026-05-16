# frozen_string_literal: true

# Converts memory to per-user scope:
#
#   agent_memory_blocks — add user_id + value columns.
#     Old unique key: (agent_id, memory_block_id)
#     New unique key: (agent_id, memory_block_id, user_id)
#
#   archival_memories — add user_id so each user's long-term memory is isolated.
class AddUserScopedMemory < ActiveRecord::Migration[8.1]
  def change
    # ── agent_memory_blocks ──────────────────────────────────────────────────
    # Drop agent-scoped unique index — now uniqueness is per (agent, block, user).
    remove_index :agent_memory_blocks,
                 name: "index_agent_memory_blocks_on_agent_id_and_memory_block_id"

    # Value lives per-user on the join row, not on the MemoryBlock template.
    add_column :agent_memory_blocks, :value, :text, null: false, default: ""

    add_reference :agent_memory_blocks, :user, null: false, foreign_key: true

    add_index :agent_memory_blocks,
              [:agent_id, :memory_block_id, :user_id],
              unique: true,
              name: "index_agent_memory_blocks_uniqueness"

    # ── archival_memories ────────────────────────────────────────────────────
    add_reference :archival_memories, :user, null: false, foreign_key: true
  end
end
