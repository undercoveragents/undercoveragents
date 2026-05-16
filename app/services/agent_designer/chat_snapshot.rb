# frozen_string_literal: true

module AgentDesigner
  class ChatSnapshot
    def initialize(chat:)
      @chat = chat
    end

    def messages
      @messages ||= chat.messages.includes(:model, :chat, :tool_calls).order(:created_at).to_a
    end

    def child_chats
      @child_chats ||= chat.child_chats.includes(:agent, :model).order(created_at: :asc).to_a
    end

    def child_messages
      @child_messages ||= load_child_messages
    end

    def child_chat_metrics
      @child_chat_metrics ||= child_messages.group_by(&:chat_id).transform_values do |chat_messages|
        build_chat_metrics(chat_messages)
      end
    end

    def total_cost
      message_cost(messages) + child_chat_metrics.values.sum { |metrics| metrics[:cost] }
    end

    def token_totals
      own_totals = token_totals_for(messages)
      child_totals = token_totals_for(child_messages)

      own_totals.merge(child_totals) { |_key, own, child| own + child }
    end

    def message_counts
      @message_counts ||= {
        user: messages.count(&:user?),
        assistant: messages.count(&:assistant?),
        system: messages.count(&:system?),
        tool: messages.count(&:tool?),
      }
    end

    def visible_messages(limit:)
      messages.last(limit)
    end

    private

    attr_reader :chat

    def load_child_messages
      return [] if child_chats.empty?

      Message.where(chat_id: child_chats.map(&:id))
             .includes(:model, :chat, :tool_calls)
             .order(:created_at)
             .to_a
    end

    def build_chat_metrics(chat_messages)
      {
        cost: message_cost(chat_messages),
        tokens: {
          input: chat_messages.sum(&:total_input_activity_tokens),
          output: chat_messages.sum { |message| message.output_tokens.to_i },
        },
      }
    end

    def message_cost(records)
      records.sum { |message| message.calculate_cost || 0 }
    end

    def token_totals_for(records)
      {
        input: records.sum { |message| message.input_tokens.to_i },
        output: records.sum { |message| message.output_tokens.to_i },
        cached: records.sum { |message| message.cached_tokens.to_i },
        cache_creation: records.sum { |message| message.cache_creation_tokens.to_i },
        thinking: records.sum { |message| message.thinking_tokens.to_i },
      }
    end
  end
end
