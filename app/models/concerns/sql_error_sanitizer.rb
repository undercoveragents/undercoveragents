# frozen_string_literal: true

module SqlErrorSanitizer
  private

  def sanitize_error(message)
    message.to_s
           .gsub(/password=[^\s&]+/i, "password=[FILTERED]")
           .gsub(%r{://[^@]+@}, "://[FILTERED]@")
           .gsub(/secret[=:]\s*\S+/i, "secret=[FILTERED]")
           .truncate(500)
  end
end
