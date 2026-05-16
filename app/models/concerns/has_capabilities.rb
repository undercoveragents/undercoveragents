# frozen_string_literal: true

# Provides a generic capability system for agents backed by the agent's
# +configuration+ JSONB column.
#
# Capabilities are stored as a hash under +configuration["capabilities"]+:
#
#   {
#     "chat_title_generator" => { "enabled" => true, "max_length" => 50, ... },
#     "memory" => { "enabled" => true, "model_id" => "text-embedding-3-small", ... }
#   }
#
# Each key maps to a +CapabilityPlugin+ configurator class.
#
# Usage:
#   agent.capability(:chat_title_generator)       # => configurator object
#   agent.capability_enabled?(:chat_title_generator) # => true/false
#   agent.configured_capabilities               # => Array of CapabilityEntry structs
#
module HasCapabilities
  extend ActiveSupport::Concern

  # Lightweight wrapper that quacks like the old Capability AR model
  # so EventDispatcher and other consumers keep working.
  CapabilityEntry = Struct.new(:capability_type, :enabled, :configuration, :agent) do
    def capability_key
      capability_type.to_sym
    end

    def configurator
      @configurator ||= resolve_configurator
    end

    private

    def resolve_configurator
      klass = CapabilityPlugin.resolve(capability_type)
      return nil unless klass

      configurator = klass.new((configuration || {}).except("enabled").symbolize_keys)
      configurator._agent_record = agent if configurator.respond_to?(:_agent_record=)
      configurator
    rescue StandardError
      nil
    end

    public

    def type_label
      CapabilityPlugin.label_for(capability_type) || capability_type.to_s.humanize
    end

    def method_missing(method, ...)
      config = configurator
      return config.public_send(method, ...) if config.respond_to?(method)

      super
    end

    def respond_to_missing?(method, include_private = false)
      configurator.respond_to?(method, include_private) || super
    end
  end

  module ClassMethods
    def capability_types
      CapabilityPlugin.type_map.transform_keys(&:to_sym)
    end
  end

  # Returns the type-specific configurator for the given key.
  # If no config exists yet, returns a new instance with defaults.
  def capability(key)
    capability_type = key.to_s
    klass = CapabilityPlugin.resolve(capability_type)
    return nil unless klass

    cap_config = capabilities_hash[capability_type]
    configurator = if cap_config.present?
                     klass.new(cap_config.except("enabled").symbolize_keys)
                   else
                     klass.new
                   end
    configurator._agent_record = self if configurator.respond_to?(:_agent_record=)
    configurator
  end

  # Returns true if the capability is present and enabled.
  def capability_enabled?(key)
    capability_type = key.to_s
    return false unless CapabilityPlugin.resolve(capability_type)

    cap_config = capabilities_hash[capability_type]
    cap_config.present? && cap_config["enabled"] != false
  end

  # Returns all enabled capabilities as CapabilityEntry structs.
  def configured_capabilities
    capabilities_hash.filter_map do |type, config|
      next unless config.is_a?(Hash)
      next unless config["enabled"] != false

      CapabilityEntry.new(
        capability_type: type,
        enabled: config["enabled"] != false,
        configuration: config.except("enabled"),
        agent: self,
      )
    end
  end

  # Returns RubyLLM::Tool instances contributed by enabled capabilities.
  def capability_tools(parent_chat: nil)
    configured_capabilities.flat_map do |cap|
      configurator = cap.configurator
      next [] unless configurator.respond_to?(:tools_for)

      Array(configurator.tools_for(agent: self, parent_chat:))
    rescue StandardError => e
      Rails.logger.error "[HasCapabilities] tools_for failed for #{cap.capability_type}: #{e.message}"
      []
    end
  end

  # Returns system prompt additions contributed by enabled capabilities.
  def capability_system_prompt_additions(user: nil)
    configured_capabilities.filter_map do |cap|
      configurator = cap.configurator
      next unless configurator.respond_to?(:system_prompt_addition_for)

      addition = configurator.system_prompt_addition_for(agent: self, user:)
      addition.presence
    rescue StandardError => e
      Rails.logger.error "[HasCapabilities] system_prompt_addition_for failed for #{cap.capability_type}: #{e.message}"
      nil
    end
  end

  # ── Capability config write helpers ──

  def set_capability_config(key, config_hash, enabled: true)
    caps = capabilities_hash.dup
    caps[key.to_s] = (config_hash || {}).merge("enabled" => enabled)
    self.configuration = (configuration || {}).merge("capabilities" => caps)
  end

  def remove_capability_config(key)
    caps = capabilities_hash.dup
    caps.delete(key.to_s)
    self.configuration = (configuration || {}).merge("capabilities" => caps)
  end

  private

  def capabilities_hash
    (configuration.is_a?(Hash) ? configuration["capabilities"] : nil) || {}
  end
end
