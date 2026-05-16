# frozen_string_literal: true

module AgentDesigner
  module ChatFormatting
    CONTENT_PREVIEW_LIMIT = 240
    FULL_VALUE_LIMIT = 4_000

    private

    def format_cost(value)
      return "0.000000" if value.blank?

      format("%.6f", value)
    end

    def format_time(value)
      value&.iso8601(3) || "-"
    end

    def quoted(value)
      value.to_s.inspect
    end

    def render_value(value, full:)
      return "None." if blank_value?(value)

      text = stringify_value(value)
      truncate_text(text, full ? FULL_VALUE_LIMIT : CONTENT_PREVIEW_LIMIT)
    end

    def blank_value?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def stringify_value(value)
      case value
      when Hash, Array
        JSON.pretty_generate(value)
      else
        value.to_s
      end
    end

    def truncate_text(text, limit)
      return text if text.length <= limit

      "#{text[0, limit - 15]}... (truncated)"
    end
  end
end
