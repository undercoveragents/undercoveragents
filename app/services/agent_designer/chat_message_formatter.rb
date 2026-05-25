# frozen_string_literal: true

module AgentDesigner
  class ChatMessageFormatter
    include ChatFormatting

    def initialize(full:)
      @full = full
    end

    def format_message(message, position:)
      [
        "",
        "### Message #{position}",
        *metadata_lines(message),
        *tool_lines(message),
        *content_lines(message),
      ].compact
    end

    private

    attr_reader :full

    def metadata_lines(message)
      [
        "- id: `#{message.id}`",
        "- role: #{message.role}",
        "- created_at: #{format_time(message.created_at)}",
        "- model: #{message.model&.model_id || message.chat&.model&.model_id || "-"}",
        "- duration_ms: #{message.duration_ms || "-"}",
        "- cost_usd: #{format_cost(message.effective_cost)}",
        "- input_tokens: #{message.input_tokens.to_i}",
        "- output_tokens: #{message.output_tokens.to_i}",
        "- cached_tokens: #{message.cached_tokens.to_i}",
        "- cache_creation_tokens: #{message.cache_creation_tokens.to_i}",
        "- thinking_tokens: #{message.thinking_tokens.to_i}",
      ]
    end

    def tool_lines(message)
      summary_lines = tool_summary_lines(message)
      return summary_lines if message.tool_calls.empty?

      summary_lines + ["- tool_call_details:"] + message.tool_calls.flat_map { |tool_call| tool_call_lines(tool_call) }
    end

    def tool_summary_lines(message)
      return ["- tool_call_id: #{message.tool_call_id || "-"}"] if message.tool?
      return ["- tool_calls: #{message.tool_calls.size}"] if message.tool_calls.any?

      []
    end

    def tool_call_lines(tool_call)
      [
        "  - name=`#{tool_call.name}` id=`#{tool_call.id}`",
        "    external_id=`#{tool_call.tool_call_id}` duration_ms=#{tool_call.duration_ms || "-"}",
        render_multiline("arguments", tool_call.arguments, indent: 4),
      ]
    end

    def content_lines(message)
      lines = []
      lines << render_multiline("thinking", message.thinking_text, indent: 2) if message.thinking_text.present?
      if message.thinking_signature.present?
        lines << render_multiline("thinking_signature", message.thinking_signature, full: false, indent: 2)
      end
      lines << render_multiline("content", message.content, indent: 2)
      lines << render_multiline("content_raw", message.content_raw, indent: 2) if message.content_raw.present?
      lines
    end

    def render_multiline(label, value, indent:, full: self.full)
      rendered = render_value(value, full:)
      prefix = " " * indent
      return "#{prefix}#{label}: #{rendered}" unless rendered.include?("\n")

      nested_prefix = " " * (indent + 2)
      lines = ["#{prefix}#{label}:"]
      rendered.each_line { |line| lines << "#{nested_prefix}#{line.rstrip}" }
      lines.join("\n")
    end
  end
end
