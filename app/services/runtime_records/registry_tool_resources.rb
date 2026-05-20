# frozen_string_literal: true

module RuntimeRecords
  module RegistryToolResources
    private

    def register_tool
      register(
        "tool",
        label: "Tool",
        model_class: Tool,
        permitted_attributes: RuntimeRecords::TOOL_PERMITTED_ATTRIBUTES,
        scope_resolver: method(:tool_scope),
        base_attributes: method(:tool_base_attributes),
        clone_supported: true,
        default_page: "show",
        page_resolver: method(:tool_page_path),
        create_handler: method(:tool_create),
        update_handler: method(:tool_update),
      )
    end

    def tool_scope(context)
      operation = tool_operation(context)

      tenant_scope = Tool.joins(:operation)
      tenant_scope = tenant_scope.where(operations: { tenant_id: context.tenant.id }) if context.tenant
      tenant_scope.where(operation:)
    end

    def tool_base_attributes(context)
      operation = tool_operation(context)
      if context.tenant && operation.tenant_id != context.tenant.id
        raise ArgumentError, "The current operation is outside the active tenant."
      end

      { operation: }
    end

    def tool_page_path(page, record:, context:)
      _context = context
      helpers = Rails.application.routes.url_helpers

      case page.to_s
      when "index"
        helpers.admin_tools_path
      when "new"
        helpers.new_admin_tool_path
      when "show"
        raise ArgumentError, "Tool page 'show' requires a record." unless record

        helpers.admin_tool_path(record)
      when "edit"
        raise ArgumentError, "Tool page 'edit' requires a record." unless record

        helpers.edit_admin_tool_path(record)
      else
        raise ArgumentError, "Unknown page '#{page}' for tool. Use index, new, show, or edit."
      end
    end

    def tool_operation(context)
      operation = context.operation
      raise ArgumentError, "No current operation is available for tools." unless operation

      operation
    end

    def tool_create(context:, attributes:, authorize:, **)
      operation = tool_operation(context)
      manager = ::Tools::AdminManager.new
      tool = manager.build(
        operation:,
        tool_type: attributes.fetch("tool_type"),
        tool_attributes: attributes.slice(*::Tools::AdminManager::TOOL_ATTRIBUTE_KEYS),
        toolable_attributes: attributes["toolable_attributes"],
      )
      authorize.call(tool, :create?)
      tool.save!
      tool
    end

    def tool_update(record:, attributes:, **)
      requested_tool_type = attributes["tool_type"].presence
      if requested_tool_type.present? && requested_tool_type != record.tool_type
        raise ArgumentError, "Tool type cannot be changed once the tool exists."
      end

      ::Tools::AdminManager.new.update!(
        tool: record,
        tool_attributes: attributes.slice(*::Tools::AdminManager::TOOL_ATTRIBUTE_KEYS),
        toolable_attributes: attributes["toolable_attributes"],
      )
    end
  end
end
