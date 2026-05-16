# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("connector_authentication") do
  name "Authentication"
  version "1.0.0"
  author "Undercover Agents"
  description "Connect to external authentication providers (Keycloak, etc.) " \
              "to enable SSO sign-in for your users."
  icon "fa-solid fa-shield-halved"
  category [:connector]
  add_connector "Authentication"
end
