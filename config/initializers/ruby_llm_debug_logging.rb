# frozen_string_literal: true

require "undercover_agents/ruby_llm_debug_logging"

Rails.application.config.to_prepare do
  patch = UndercoverAgents::RubyLlmDebugLogging::ProviderPatch
  RubyLLM::Provider.prepend(patch) unless patch < RubyLLM::Provider
end
