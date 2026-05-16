# frozen_string_literal: true

require "faraday"

keycloak_ca_file = ENV["KEYCLOAK_CA_FILE"].presence
keycloak_ssl_verify = ActiveModel::Type::Boolean.new.cast(ENV.fetch("KEYCLOAK_SSL_VERIFY", "true"))
keycloak_base_url = ENV.fetch("KEYCLOAK_BASE_URL", "/auth")

ENV["SSL_CERT_FILE"] = keycloak_ca_file if keycloak_ca_file

# omniauth-keycloak fetches OIDC discovery with Faraday.get directly.
# When SSL verification is explicitly disabled, mirror that at Faraday default level
# so discovery and token exchange use the same behavior.
unless keycloak_ssl_verify
  Faraday.default_connection_options[:ssl] ||= {}
  Faraday.default_connection_options[:ssl][:verify] = false
end

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :keycloak_openid,
           name: "keycloak",
           setup: lambda { |env|
             strategy = env["omniauth.strategy"]
             connector = Connectors::Authentication.for_provider("keycloak")

             if connector&.enabled?
               ssl_options = { verify: keycloak_ssl_verify }
               ssl_options[:ca_file] = keycloak_ca_file if keycloak_ca_file

               strategy.options[:client_id] = connector.client_id
               strategy.options[:client_secret] = connector.client_secret
               strategy.options[:client_options] = {
                 site: connector.site_url,
                 realm: connector.realm,
                 base_url: keycloak_base_url,
                 ssl: ssl_options,
               }
             end
           }

  provider :google_oauth2,
           name: "google",
           setup: lambda { |env|
             strategy = env["omniauth.strategy"]
             connector = Connectors::Authentication.for_provider("google")
             if strategy.on_request_path?
               pending_signup = Cloud::PendingSignup.from_request_params(strategy.request.params)

               if pending_signup.present?
                 Cloud::PendingSignup.store(
                   strategy.session,
                   provider: pending_signup.provider,
                 )
               else
                 Cloud::PendingSignup.clear(strategy.session)
               end
             end

             next unless connector&.enabled?

             strategy.options[:client_id] = connector.client_id
             strategy.options[:client_secret] = connector.client_secret
             strategy.options[:scope] = "email,profile"
             strategy.options[:prompt] = "select_account"
             strategy.options[:access_type] = "online"
           }
end

OmniAuth.config.logger = Rails.logger
