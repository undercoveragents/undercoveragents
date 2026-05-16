# frozen_string_literal: true

RubyLLM.configure do |config|
  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true

  # Provider API keys are configured via LLM Provider connectors in the UI.
  # Create an LLM Provider connector to connect to OpenAI, Anthropic, Gemini, etc.
  # Each agent references an LLM connector (or defaults to the first enabled one).
end
