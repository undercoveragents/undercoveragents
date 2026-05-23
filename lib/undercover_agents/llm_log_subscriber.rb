# frozen_string_literal: true

module UndercoverAgents
  class LlmLogSubscriber
    EVENTS = [
      "llm.generation.undercover_agents",
      "llm.generation_error.undercover_agents",
      "llm.tool_call.undercover_agents",
      "llm.stream_chunk.undercover_agents",
    ].freeze

    def self.attach!
      return if @attached

      EVENTS.each do |event_name|
        ActiveSupport::Notifications.subscribe(event_name) do |name, _start, _finish, _id, payload|
          new.log(name, payload)
        end
      end
      @attached = true
    end

    def log(name, payload)
      Rails.logger.debug { "[LLM instrumentation] #{name} #{safe_payload(payload).to_json}" }
    end

    private

    def safe_payload(payload)
      payload.except(:exception, :exception_object).compact
    end
  end
end
