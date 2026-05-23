# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :api_client, :chat, :llm_trace_id, :operation, :tenant, :user
end
