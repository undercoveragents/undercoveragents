# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :api_client, :chat, :operation, :tenant, :user
end
