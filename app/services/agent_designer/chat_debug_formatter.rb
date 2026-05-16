# frozen_string_literal: true

module AgentDesigner
  class ChatDebugFormatter
    include ChatFormatting

    DEFAULT_RECENT_LIMIT = 5
    MAX_RECENT_LIMIT = 10
    DEFAULT_MESSAGE_LIMIT = 6
    MAX_MESSAGE_LIMIT = 20
    SELECTORS = ["latest", "recent"].freeze

    def initialize(agent:)
      @agent = agent
    end

    def format_chat(chat, detail: nil, message_limit: nil)
      snapshot = AgentDesigner::ChatSnapshot.new(chat:)
      visible_messages = snapshot.visible_messages(limit: normalized_message_limit(message_limit))
      omitted_count = snapshot.messages.size - visible_messages.size
      parts = ["## Agent Chat", *overview_lines(chat, snapshot)]

      append_section(parts, "Parent Chat", parent_chat_lines(chat))
      append_section(parts, "Child Chats (#{snapshot.child_chats.size})", child_chat_lines(snapshot))
      append_section(
        parts,
        "Messages (showing #{visible_messages.size})",
        message_lines(visible_messages, omitted_count:, detail:),
      )

      parts.join("\n")
    end

    def format_recent_chats(chats, limit: nil)
      selected_chats = Array(chats).first(normalized_recent_limit(limit))
      return "No chats found for '#{agent.name}'." if selected_chats.empty?

      parts = ["## Recent Agent Chats (#{selected_chats.size})"]
      selected_chats.each do |chat|
        snapshot = ChatSnapshot.new(chat:)
        parts << format_recent_chat_line(chat, snapshot)
      end
      parts.join("\n")
    end

    def normalized_selector(selector)
      value = selector.to_s.presence || "latest"
      raise ArgumentError, "selector must be one of: #{SELECTORS.join(", ")}" unless value.in?(SELECTORS)

      value
    end

    private

    attr_reader :agent

    def overview_lines(chat, snapshot)
      chat_identity_lines(chat) +
        chat_context_lines(chat, snapshot) +
        message_count_lines(snapshot) +
        token_lines(snapshot)
    end

    def chat_identity_lines(chat)
      [
        "- agent: #{agent.name} (id: #{agent.id}, slug: `#{agent.slug}`)",
        "- chat_id: `#{chat.id}`",
        "- title: #{chat.display_title}",
        "- status: #{chat.status}",
        "- execution_context: #{chat.execution_context}",
        "- user_id: #{chat.user_id || "-"}",
        "- model: #{chat.model&.model_id || "-"}",
        "- model_db_id: #{chat.model_id || "-"}",
      ]
    end

    def chat_context_lines(chat, snapshot)
      [
        "- parent_chat_id: #{chat.parent_chat_id || "-"}",
        "- child_chats: #{snapshot.child_chats.size}",
        "- messages: #{snapshot.messages.size}",
        "- created_at: #{format_time(chat.created_at)}",
        "- updated_at: #{format_time(chat.updated_at)}",
      ]
    end

    def message_count_lines(snapshot)
      [
        "- user_messages: #{snapshot.message_counts[:user]}",
        "- assistant_messages: #{snapshot.message_counts[:assistant]}",
        "- system_messages: #{snapshot.message_counts[:system]}",
        "- tool_messages: #{snapshot.message_counts[:tool]}",
      ]
    end

    def token_lines(snapshot)
      [
        "- total_cost_usd: #{format_cost(snapshot.total_cost)}",
        "- input_tokens: #{snapshot.token_totals[:input]}",
        "- output_tokens: #{snapshot.token_totals[:output]}",
        "- cached_tokens: #{snapshot.token_totals[:cached]}",
        "- cache_creation_tokens: #{snapshot.token_totals[:cache_creation]}",
        "- thinking_tokens: #{snapshot.token_totals[:thinking]}",
      ]
    end

    def parent_chat_lines(chat)
      return [] unless chat.parent_chat

      [
        "- chat_id: `#{chat.parent_chat.id}`",
        "- title: #{chat.parent_chat.display_title}",
        "- agent: #{chat.parent_chat.agent&.name || "-"}",
      ]
    end

    def child_chat_lines(snapshot)
      snapshot.child_chats.map do |child_chat|
        metrics = snapshot.child_chat_metrics.fetch(child_chat.id, default_child_metrics)
        [
          "- chat_id=`#{child_chat.id}`",
          "title=#{quoted(child_chat.display_title)}",
          "status=#{child_chat.status}",
          "agent=#{quoted(child_chat.agent&.name || "-")}",
          "messages=#{child_chat.messages_count}",
          "input_tokens=#{metrics.dig(:tokens, :input) || 0}",
          "output_tokens=#{metrics.dig(:tokens, :output) || 0}",
          "cost_usd=#{format_cost(metrics[:cost])}",
        ].join(" ")
      end
    end

    def message_lines(messages, omitted_count:, detail:)
      return ["No messages found."] if messages.empty?

      formatter = AgentDesigner::ChatMessageFormatter.new(full: detail.to_s == "full")
      lines = messages.each_with_index.flat_map do |message, index|
        formatter.format_message(message, position: index + 1)
      end
      lines << "- earlier_messages_omitted: #{omitted_count}" if omitted_count.positive?
      lines
    end

    def append_section(parts, title, lines)
      return if lines.empty?

      parts << ""
      parts << "## #{title}"
      parts.concat(lines)
    end

    def normalized_recent_limit(limit)
      parsed = Integer(limit || DEFAULT_RECENT_LIMIT, exception: false) || DEFAULT_RECENT_LIMIT
      parsed.clamp(1, MAX_RECENT_LIMIT)
    end

    def normalized_message_limit(limit)
      parsed = Integer(limit || DEFAULT_MESSAGE_LIMIT, exception: false) || DEFAULT_MESSAGE_LIMIT
      parsed.clamp(1, MAX_MESSAGE_LIMIT)
    end

    def format_recent_chat_line(chat, snapshot)
      [
        "- chat_id=`#{chat.id}`",
        "title=#{quoted(chat.display_title)}",
        "status=#{chat.status}",
        "execution_context=#{chat.execution_context}",
        "updated_at=#{format_time(chat.updated_at)}",
        "messages=#{snapshot.messages.size}",
        "child_chats=#{snapshot.child_chats.size}",
        "input_tokens=#{snapshot.token_totals[:input]}",
        "output_tokens=#{snapshot.token_totals[:output]}",
        "cost_usd=#{format_cost(snapshot.total_cost)}",
        ("parent_chat_id=#{chat.parent_chat_id}" if chat.parent_chat_id.present?),
      ].compact.join(" ")
    end

    def default_child_metrics
      { cost: 0, tokens: {} }
    end
  end
end
