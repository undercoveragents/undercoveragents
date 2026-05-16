# frozen_string_literal: true

module AgentDesigner
  class ManageCapabilityTool < RubyLLM::Tool
    include AgentLookup
    include PolicyAuthorizable

    ACTIONS = {
      "set" => :set,
      "update" => :set,
      "configure" => :set,
      "remove" => :remove,
      "delete" => :remove,
    }.freeze

    description "Enable, update, or remove an agent capability using the capability plugin schema."

    param :action,
          desc: "Capability mutation to perform: 'set' or 'remove'."

    param :capability_key,
          desc: "Capability key from list_resources(kind: 'capabilities'), for example 'chat_title_generator'."

    param :agent_id,
          desc: "Optional numeric ID or slug. Omit to edit the current agent from page context.",
          required: false

    param :config,
          desc: "Optional capability config hash or JSON object string. For set/update, provided keys are merged " \
                "with the current capability config or plugin defaults.",
          required: false

    def initialize(runtime_context:, current_agent: nil)
      super()
      @runtime_context = runtime_context
      @current_agent = current_agent
    end

    def name = "manage_capability"

    def execute(action:, capability_key:, agent_id: nil, config: nil)
      normalized_action = ACTIONS[action.to_s]
      return "Error: Unknown action '#{action}'. Use set or remove." unless normalized_action

      agent = resolve_agent(agent_id)
      return missing_agent_message if agent.nil?

      capability_class = CapabilityPlugin.resolve(capability_key)
      if capability_class.nil?
        return "Error: Unknown capability '#{capability_key}'. Use list_resources(kind: 'capabilities')."
      end

      if normalized_action == :set
        set_capability(agent, capability_key, capability_class, config)
      else
        remove_capability(agent, capability_key)
      end
    rescue ActiveRecord::RecordInvalid => e
      "Error: #{e.record.errors.full_messages.to_sentence}"
    rescue ArgumentError, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing capability: #{e.message}"
    end

    private

    def set_capability(agent, capability_key, capability_class, raw_config)
      authorize_policy!(agent, :update?, user: @runtime_context.user)

      normalized_existing = normalized_existing_config(agent, capability_key, capability_class)
      normalized_config = normalize_config_hash(raw_config)
      validated_updates = validate_incoming_config(capability_class, normalized_config)
      merged_config = normalized_existing.merge(validated_updates)

      configurator = capability_class.new
      configurator._agent_record = agent if configurator.respond_to?(:_agent_record=)
      configurator.assign_attributes(merged_config)
      raise ArgumentError, configurator.errors.full_messages.to_sentence unless configurator.valid?

      agent.set_capability_config(capability_key, configurator.to_configuration)
      agent.save!
      notify_capability_enabled(configurator, agent)
      refreshed = broadcast_refresh?(agent)

      capability_set_message(agent, capability_key, configurator, refreshed:)
    end

    def remove_capability(agent, capability_key)
      authorize_policy!(agent, :update?, user: @runtime_context.user)

      stored_config = stored_capability_config(agent, capability_key)
      return "Capability `#{capability_key}` is not currently assigned to #{agent.name}." if stored_config.blank?

      agent.remove_capability_config(capability_key)
      agent.save!
      refreshed = broadcast_refresh?(agent)

      [
        "Capability removed successfully.",
        "- Agent: #{agent.name} (`#{agent.id}`)",
        "- Capability: `#{capability_key}`",
        refresh_note(refreshed),
      ].join("\n")
    end

    def capability_set_message(agent, capability_key, configurator, refreshed:)
      lines = [
        "Capability configured successfully.",
        "- Agent: #{agent.name} (`#{agent.id}`)",
        "- Capability: `#{capability_key}` — #{configurator.class.label}",
      ]
      summary = configurator.summary.to_s.strip
      lines << "- Summary: #{summary}" if summary.present?
      lines << "- Config: `#{JSON.generate(configurator.to_configuration)}`" if configurator.to_configuration.present?
      lines << refresh_note(refreshed) if refreshed
      lines.join("\n")
    end

    def broadcast_refresh?(agent)
      RuntimeRecords::Refresh.broadcast!(
        context: @runtime_context,
        resource: "agent",
        record: agent,
      ) == :broadcasted
    end

    def refresh_note(refreshed)
      return unless refreshed

      "Current page refresh started to show the saved agent."
    end

    def normalized_existing_config(agent, capability_key, capability_class)
      raw_config = stored_capability_config(agent, capability_key)
      return {} unless raw_config.is_a?(Hash)

      permitted_config(capability_class, raw_config)
    end

    def validate_incoming_config(capability_class, config_hash)
      permitted = permitted_config(capability_class, config_hash)
      unknown_keys = config_hash.stringify_keys.keys - permitted.keys
      return permitted if unknown_keys.empty?

      raise ArgumentError, "Unknown capability config keys: #{unknown_keys.join(", ")}"
    end

    def permitted_config(capability_class, config_hash)
      raw_params = ActionController::Parameters.new(config_hash.stringify_keys)
      capability_class.permitted_params(raw_params).to_h.stringify_keys
    end

    def normalize_config_hash(value)
      case value
      when nil
        {}
      when ActionController::Parameters
        value.to_unsafe_h.stringify_keys
      when Hash
        value.stringify_keys
      when String
        parse_config_string(value)
      else
        raise ArgumentError, "Expected config to be a hash or JSON object string."
      end
    end

    def parse_config_string(value)
      stripped = value.strip
      return {} if stripped.empty?

      parsed = JSON.parse(stripped)
      raise ArgumentError, "Expected config to be a JSON object." unless parsed.is_a?(Hash)

      parsed.stringify_keys
    rescue JSON::ParserError => e
      raise ArgumentError, e.message
    end

    def stored_capability_config(agent, capability_key)
      return {} unless agent.configuration.is_a?(Hash)

      agent.configuration.fetch("capabilities", {})[capability_key.to_s]
    end

    def notify_capability_enabled(configurator, agent)
      return unless configurator.respond_to?(:after_capability_enabled)

      configurator.after_capability_enabled(agent)
    rescue StandardError => e
      Rails.logger.error "[ManageCapabilityTool] after_capability_enabled failed: #{e.message}"
    end
  end
end
