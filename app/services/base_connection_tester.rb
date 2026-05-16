# frozen_string_literal: true

# Base class for connection testers (Database, MCP, etc.).
#
# Provides the shared Result type, success/failure helpers,
# and error sanitization. Subclasses implement `call` with
# adapter-specific connection logic.
#
class BaseConnectionTester
  include SqlErrorSanitizer

  Result = Data.define(:success?, :message, :details)

  def initialize(params)
    @params = params.symbolize_keys
  end

  def call
    failure("Unknown connector type")
  end

  private

  def success(message, details = {})
    Result.new(success?: true, message:, details:)
  end

  def failure(message, details = {})
    Result.new(success?: false, message:, details:)
  end
end
