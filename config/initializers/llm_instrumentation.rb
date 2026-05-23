# frozen_string_literal: true

require Rails.root.join("lib/undercover_agents/llm_log_subscriber").to_s

UndercoverAgents::LlmLogSubscriber.attach!
