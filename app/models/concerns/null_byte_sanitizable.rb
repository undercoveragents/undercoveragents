# frozen_string_literal: true

# Provides methods for sanitizing null bytes (\u0000) from data.
# PostgreSQL text and JSONB columns cannot store null bytes and will raise
# PG::UntranslatableCharacter errors when attempting to save them.
# Null bytes can appear in LLM responses or tool outputs.
#
# @example Usage in a model
#   class Message < ApplicationRecord
#     include NullByteSanitizable
#
#     before_save :sanitize_content_null_bytes
#
#     private
#
#     def sanitize_content_null_bytes
#       self.content = sanitize_null_bytes(content)
#     end
#   end
module NullByteSanitizable
  extend ActiveSupport::Concern

  # Sanitizes null bytes (\u0000) from a string.
  # @param text [String, nil] The text to sanitize
  # @return [String, nil] The sanitized text, or nil if input was blank
  def sanitize_null_bytes(text)
    return text if text.blank?

    text.delete("\u0000")
  end

  # Deep sanitizes null bytes from any data structure (String, Hash, Array).
  # Used for JSON/JSONB columns that may contain nested null bytes.
  # @param data [String, Hash, Array, Object] The data to sanitize
  # @return [String, Hash, Array, Object] The sanitized data
  def deep_sanitize_null_bytes(data)
    case data
    when String
      sanitize_null_bytes(data)
    when Hash
      data.transform_values { |v| deep_sanitize_null_bytes(v) }
    when Array
      data.map { |v| deep_sanitize_null_bytes(v) }
    else
      data
    end
  end
end
