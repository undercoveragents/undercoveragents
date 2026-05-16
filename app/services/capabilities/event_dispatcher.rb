# frozen_string_literal: true

module Capabilities
  # Dispatches lifecycle events to all enabled capability handlers for a given agent.
  #
  # Each capability configurator class registers its service handler via
  # +event_handler_class+.
  # The dispatcher iterates over all enabled capabilities of the agent resolved from
  # the payload, finds the corresponding handler, and delegates the event.
  #
  # Usage:
  #   Capabilities::EventDispatcher.dispatch(:chat_response_completed, chat: chat)
  #
  # Supported events:
  #   :chat_response_completed — fired after a chat response is finalised
  #
  class EventDispatcher
    def self.dispatch(event, **payload)
      new(event, payload).dispatch
    end

    def initialize(event, payload)
      @event = event
      @payload = payload
    end

    # Resolves the agent from the payload, then calls every enabled capability
    # handler that registers the event_handler_class class method.
    # Returns true if at least one handler was invoked, false otherwise.
    def dispatch
      agent = resolve_agent
      return false unless agent

      handled = false

      agent.configured_capabilities.each do |capability|
        configurator = capability.configurator
        next unless configurator

        handler_class = configurator.class.event_handler_class
        next unless handler_class

        handler_class.new(configurator).handle(@event, **@payload)
        handled = true
      rescue StandardError => e
        Rails.logger.error "[Capabilities::EventDispatcher] #{capability.capability_key} raised " \
                           "on #{@event}: #{e.message}"
      end

      handled
    end

    private

    def resolve_agent
      @payload[:chat]&.agent
    end
  end
end
