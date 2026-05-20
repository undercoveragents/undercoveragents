# frozen_string_literal: true

require_relative "app/services/web_search/clients/duck_duck_go_client"

UndercoverAgents::PluginSystem.register("web_search_duckduckgo") do
  name "DuckDuckGo Web Search"
  version "1.0.0"
  author "Undercover Agents"
  description "Plugin-backed public web search client using DuckDuckGo HTML results."
  icon "fa-solid fa-magnifying-glass"
  category [:general]
end

WebSearch::SearchClientRegistry.register(
  "duckduckgo",
  "WebSearch::Clients::DuckDuckGoClient",
  default: true,
)
