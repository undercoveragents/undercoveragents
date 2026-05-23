# frozen_string_literal: true

module RuntimeRecords
  module RegistryAgentResources
    private

    def register_agent
      register(
        "agent",
        label: "Agent",
        model_class: Agent,
        permitted_attributes: RuntimeRecords::AGENT_PERMITTED_ATTRIBUTES,
        scope_resolver: method(:agent_scope),
        base_attributes: method(:agent_base_attributes),
        clone_supported: true,
        default_page: "show",
        page_resolver: method(:agent_page_path),
        create_handler: nil,
        update_handler: method(:agent_update),
      )
    end

    def agent_scope(context)
      operation = agent_operation(context)

      tenant_scope = Agent.joins(:operation)
      tenant_scope = tenant_scope.where(operations: { tenant_id: context.tenant.id }) if context.tenant
      tenant_scope.where(operation:)
    end

    def agent_base_attributes(context)
      operation = agent_operation(context)
      if context.tenant && operation.tenant_id != context.tenant.id
        raise ArgumentError, "The current operation is outside the active tenant."
      end

      preferences = SystemPreference.current_settings(tenant: context.tenant)

      {
        operation:,
        agent_type: AgentConfiguration::DEFAULT_AGENT_TYPE,
        temperature: Agent::DEFAULT_TEMPERATURE,
        enabled: true,
        llm_connector_id: preferences[:llm_connector_id],
        model_id: preferences[:model_id],
      }.compact
    end

    def agent_page_path(page, record:, context:)
      _context = context
      helpers = Rails.application.routes.url_helpers
      page_name = page.to_s

      return helpers.admin_agents_path if page_name == "index"
      return helpers.new_admin_agent_path if page_name == "new"

      agent_record_page_path(page_name, record, helpers)
    end

    def agent_record_page_path(page_name, record, helpers)
      case page_name
      when "show"
        raise ArgumentError, "Agent page 'show' requires a record." unless record

        helpers.admin_agent_path(record)
      when "edit"
        raise ArgumentError, "Agent page 'edit' requires a record." unless record

        helpers.edit_admin_agent_path(record)
      when "prompt_preview"
        raise ArgumentError, "Agent page 'prompt_preview' requires a record." unless record

        helpers.prompt_preview_admin_agent_path(record)
      else
        raise ArgumentError, "Unknown page '#{page_name}' for agent. Use index, new, show, edit, or prompt_preview."
      end
    end

    def agent_operation(context)
      operation = context.operation
      raise ArgumentError, "No current operation is available for agents." unless operation

      operation
    end

    def agent_update(record:, attributes:, **)
      record.update!(AgentAttributesNormalizer.call(record:, attributes:))
      record
    end
  end
end
