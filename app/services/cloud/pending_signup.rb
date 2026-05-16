# frozen_string_literal: true

module Cloud
  class PendingSignup
    Entry = Data.define(:provider)

    FLOW = "tenant_admin"
    PROVIDER = "google"
    SESSION_KEY = "cloud_pending_signup"
    REQUEST_PARAM_KEY = "cloud_signup"

    class << self
      def load(session)
        payload = session[SESSION_KEY]
        return unless payload.is_a?(Hash)

        provider = payload["provider"].to_s
        return if provider.blank?

        Entry.new(provider:)
      end

      def store(session, provider:)
        session[SESSION_KEY] = {
          "provider" => provider,
        }
      end

      def clear(session)
        session.delete(SESSION_KEY)
      end

      def from_request_params(params)
        payload = params[REQUEST_PARAM_KEY]
        return unless payload.respond_to?(:[])
        return unless payload["flow"].to_s == FLOW

        Entry.new(provider: PROVIDER)
      end
    end
  end
end
