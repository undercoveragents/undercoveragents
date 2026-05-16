# frozen_string_literal: true

module BuiltinAgents
  class Synchronizer
    Result = Data.define(:created_keys, :restored_keys)

    def self.ensure_present!(keys: nil, tenant: Current.tenant || Tenant.default_tenant)
      new(keys:, restore: false, tenant:).call
    end

    def self.restore!(key, tenant: Current.tenant || Tenant.default_tenant)
      new(keys: [key], restore: true, tenant:).call
    end

    def self.restore_all!(tenant: Current.tenant || Tenant.default_tenant)
      new(restore: true, tenant:).call
    end

    def initialize(tenant: Current.tenant || Tenant.default_tenant, keys: nil, restore: false)
      @keys = Array(keys).compact.map(&:to_s).presence
      @restore = restore
      @tenant = tenant
    end

    def call
      definitions = load_definitions
      return Result.new(created_keys: [], restored_keys: []) if definitions.empty?

      headquarter = ensure_headquarter!
      skill_catalog_ids_by_key = sync_builtin_skill_catalogs!(definitions, headquarter)
      created_keys, restored_keys = sync_agents!(definitions, headquarter, skill_catalog_ids_by_key)

      Result.new(created_keys:, restored_keys:)
    end

    private

    def sync_agents!(definitions, headquarter, skill_catalog_ids_by_key)
      existing_agents = builtin_agents_for(definitions).index_by(&:builtin_key)
      result_keys = { created: [], restored: [] }

      Agent.transaction do
        stale_builtin_agents(definitions).find_each(&:destroy!) if @keys.blank?
        definitions.each do |definition|
          sync_agent!(definition, existing_agents, headquarter, skill_catalog_ids_by_key, result_keys)
        end
        sync_subagents!(definitions, existing_agents)
      end

      [result_keys[:created], result_keys[:restored]]
    end

    def builtin_agents_for(definitions)
      @tenant.agents.builtin.where("configuration ->> 'builtin_key' IN (?)", definitions.map(&:key))
    end

    def sync_agent!(definition, existing_agents, headquarter, skill_catalog_ids_by_key, result_keys)
      agent = existing_agents[definition.key] || Agent.new
      created = agent.new_record?

      apply_locked_attributes(agent, definition, headquarter, skill_catalog_ids_by_key)
      apply_editable_attributes(agent, definition) if created || @restore
      agent.save!

      existing_agents[definition.key] = agent
      result_keys[:created] << definition.key if created
      result_keys[:restored] << definition.key if @restore && !created
    end

    def load_definitions
      definitions = BuiltinAgents::DefinitionLoader.load_all
      return definitions if @keys.blank?

      definitions_by_key = definitions.index_by(&:key)
      missing = @keys - definitions_by_key.keys
      raise "Unknown builtin agent keys: #{missing.join(", ")}" if missing.any?

      expand_requested_definitions(definitions_by_key)
    end

    def ensure_headquarter!
      @tenant.ensure_core_resources!
      @tenant.headquarter_operation
    end

    def stale_builtin_agents(definitions)
      @tenant.agents.builtin.where.not("configuration ->> 'builtin_key' IN (?)", definitions.map(&:key))
    end

    def apply_locked_attributes(agent, definition, headquarter, skill_catalog_ids_by_key)
      agent.operation = headquarter
      definition.locked_attributes.each do |attribute, value|
        agent.public_send(:"#{attribute}=", value)
      end
      apply_skill_catalog_assignments(agent, definition, skill_catalog_ids_by_key)
      apply_capability_assignments(agent, definition)
    end

    def apply_editable_attributes(agent, definition)
      definition.editable_attributes.each do |attribute, value|
        agent.public_send(:"#{attribute}=", value)
      end
    end

    def expand_requested_definitions(definitions_by_key)
      expanded = {}
      missing = []
      pending = @keys.dup

      until pending.empty?
        key = pending.shift
        next if expanded.key?(key)

        definition = definitions_by_key[key]
        if definition.nil?
          missing << key
          next
        end

        expanded[key] = definition
        pending.concat(definition.subagent_keys)
      end

      raise "Unknown builtin agent keys: #{missing.uniq.join(", ")}" if missing.any?

      expanded.values.sort_by(&:key)
    end

    def sync_subagents!(definitions, existing_agents)
      definitions.each do |definition|
        agent = existing_agents[definition.key]
        next unless agent

        subagent_ids = definition.subagent_keys.filter_map { |sub_key| existing_agents[sub_key]&.id }
        next if agent.subagent_ids == subagent_ids

        agent.subagent_ids = subagent_ids
        agent.save!
      end
    end

    def sync_builtin_skill_catalogs!(definitions, headquarter)
      requested_keys = definitions.flat_map(&:skill_catalog_keys).uniq

      if @keys.blank?
        BuiltinSkills::Synchronizer.ensure_present!(tenant: @tenant)
      elsif requested_keys.any?
        BuiltinSkills::Synchronizer.ensure_present!(keys: requested_keys, tenant: @tenant)
      end

      headquarter.skill_catalogs.builtin.index_by(&:builtin_key).transform_values(&:id)
    end

    def apply_skill_catalog_assignments(agent, definition, skill_catalog_ids_by_key)
      builtin_catalog_ids = resolve_skill_catalog_ids(definition.skill_catalog_keys, skill_catalog_ids_by_key)

      agent.skill_catalog_ids = if agent.new_record? || @restore
                                  builtin_catalog_ids
                                else
                                  (agent.skill_catalog_ids | builtin_catalog_ids)
                                end
    end

    def apply_capability_assignments(agent, definition)
      builtin_capabilities = resolve_capability_configs(agent, definition)
      merged_capabilities = if agent.new_record? || @restore
                              builtin_capabilities
                            else
                              merge_builtin_capabilities(
                                agent.configuration&.fetch("capabilities", nil),
                                builtin_capabilities,
                              )
                            end

      configuration = (agent.configuration || {}).deep_dup
      if merged_capabilities.present?
        configuration["capabilities"] = merged_capabilities
      else
        configuration.delete("capabilities")
      end

      agent.configuration = configuration
    end

    def resolve_capability_configs(agent, definition)
      definition.capability_configs.each_with_object({}) do |(key, raw_config), configs|
        capability_class = CapabilityPlugin.resolve(key)
        raise "Unknown builtin capability keys: #{key}" unless capability_class

        configs[key] = normalize_capability_config(agent, definition, capability_class, raw_config)
      end
    end

    def normalize_capability_config(agent, definition, capability_class, raw_config)
      config = raw_config.deep_stringify_keys
      enabled = config.key?("enabled") ? ActiveModel::Type::Boolean.new.cast(config["enabled"]) : true
      configurator = capability_class.new(config.except("enabled").symbolize_keys)
      configurator._agent_record = agent if configurator.respond_to?(:_agent_record=)

      unless configurator.valid?
        raise "Invalid builtin capability '#{capability_class.key}' for '#{definition.key}': " \
              "#{configurator.errors.full_messages.to_sentence}"
      end

      configurator.to_configuration.merge("enabled" => enabled)
    end

    def merge_builtin_capabilities(existing_capabilities, builtin_capabilities)
      existing = existing_capabilities.is_a?(Hash) ? existing_capabilities.deep_stringify_keys : {}

      existing.merge(builtin_capabilities) do |_key, current, builtin|
        current.is_a?(Hash) ? current.deep_stringify_keys : builtin
      end
    end

    def resolve_skill_catalog_ids(requested_keys, skill_catalog_ids_by_key)
      missing = requested_keys - skill_catalog_ids_by_key.keys
      raise "Unknown builtin skill catalog keys: #{missing.join(", ")}" if missing.any?

      requested_keys.filter_map { |key| skill_catalog_ids_by_key[key] }
    end
  end
end
