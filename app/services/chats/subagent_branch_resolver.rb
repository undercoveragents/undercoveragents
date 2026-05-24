# frozen_string_literal: true

module Chats
  class SubagentBranchResolver
    def self.child_chat_assignments_for(chat, messages: nil)
      new(chat, messages:).child_chat_assignments
    end

    def self.tool_call_identity(tool_call)
      return unless tool_call

      if tool_call.respond_to?(:id) && tool_call.id.present?
        tool_call.id
      elsif tool_call.respond_to?(:tool_call_id) && tool_call.tool_call_id.present?
        tool_call.tool_call_id
      else
        tool_call.object_id
      end
    end

    def initialize(chat, messages: nil)
      @chat = chat
      @messages = Array(messages).presence || default_messages
    end

    def child_chat_assignments
      return empty_assignments if child_chats.empty?

      messages.each_with_index.with_object(empty_assignments) do |(message, index), assignments|
        next unless message_window_relevant?(message)

        child_chat_map = assignments_for_message(message, next_message_for(index))
        next if child_chat_map.empty?

        assignments[message.id] = child_chat_map
      end
    end

    private

    attr_reader :chat, :messages

    def default_messages
      Chats::VisibleMessageLoader.load(chat)
    end

    def child_chats
      @child_chats ||= chat.child_chats.order(:created_at, :id).to_a
    end

    def empty_assignments
      Hash.new { |hash, key| hash[key] = {} }
    end

    def message_window_relevant?(message)
      message.assistant? && message.tool_calls.any?
    end

    def next_message_for(index)
      messages[index + 1]
    end

    def assignments_for_message(message, next_message)
      tool_calls = subagent_tool_calls_for_message(message)
      return {} if tool_calls.empty?

      window_child_chats = child_chat_window(message, next_message)
      return {} if window_child_chats.empty?

      assign_child_chats_to_tool_calls(tool_calls, window_child_chats)
    end

    def subagent_tool_calls_for_message(message)
      Array(message.tool_calls)
        .sort_by { |tool_call| [tool_call.created_at, tool_call.id.to_i] }
        .select { |tool_call| subagent_index.key?(tool_call.name.to_s) }
    end

    def child_chat_window(message, next_message)
      child_chats.select { |child_chat| child_chat_in_message_window?(child_chat, message, next_message) }
    end

    def child_chat_in_message_window?(child_chat, message, next_message)
      child_key = [child_chat.created_at, child_chat.id.to_i]
      message_key = [message.created_at, message.id.to_i]
      next_key = next_message && [next_message.created_at, next_message.id.to_i]

      tuple_compare(child_key, message_key) >= 0 && (next_key.nil? || tuple_compare(child_key, next_key).negative?)
    end

    def assign_child_chats_to_tool_calls(tool_calls, child_chats)
      remaining_child_chats = child_chats.dup

      tool_calls.each_with_object({}) do |tool_call, assignments|
        subagent = subagent_index[tool_call.name.to_s]
        next unless subagent

        matching_child_chat = remaining_child_chats.find { |child_chat| child_chat.agent_id == subagent.id }
        next unless matching_child_chat

        assignments[self.class.tool_call_identity(tool_call)] = matching_child_chat
        remaining_child_chats.delete(matching_child_chat)
      end
    end

    def subagent_index
      @subagent_index ||= if (agent = chat.agent)
                            agent.subagents.enabled.to_a.index_by { |subagent| subagent_tool_name(subagent.name) }
                          else
                            {}
                          end
    end

    def subagent_tool_name(name)
      normalized_name = name.to_s
                            .unicode_normalize(:nfkd)
                            .encode("ASCII", replace: "")
                            .gsub(/[^a-zA-Z0-9_-]/, "_")
                            .squeeze("_")
                            .gsub(/\A_|_\z/, "")
                            .downcase

      "ask_agent_#{normalized_name}"
    end

    def tuple_compare(left, right)
      left <=> right
    end
  end
end
