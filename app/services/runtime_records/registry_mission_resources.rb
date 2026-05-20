# frozen_string_literal: true

module RuntimeRecords
  module RegistryMissionResources
    private

    def register_mission
      register(
        "mission",
        label: "Mission",
        model_class: Mission,
        permitted_attributes: ["name", "description"],
        scope_resolver: method(:mission_scope),
        base_attributes: method(:mission_base_attributes),
        clone_supported: true,
        default_page: "designer",
        page_resolver: method(:mission_page_path),
        create_handler: nil,
        update_handler: nil,
      )
    end

    def mission_scope(context)
      operation = mission_operation(context)

      tenant_scope = Mission.joins(:operation)
      tenant_scope = tenant_scope.where(operations: { tenant_id: context.tenant.id }) if context.tenant
      tenant_scope.where(operation:)
    end

    def mission_base_attributes(context)
      operation = mission_operation(context)
      if context.tenant && operation.tenant_id != context.tenant.id
        raise ArgumentError, "The current operation is outside the active tenant."
      end

      { operation: }
    end

    def mission_page_path(page, record:, context:)
      _context = context
      helpers = Rails.application.routes.url_helpers

      case page.to_s
      when "index"
        helpers.admin_missions_path
      when "new"
        helpers.new_admin_mission_path
      when "edit"
        raise ArgumentError, "Mission page 'edit' requires a record." unless record

        helpers.edit_admin_mission_path(record)
      when "designer"
        raise ArgumentError, "Mission page 'designer' requires a record." unless record

        helpers.designer_admin_mission_path(record)
      else
        raise ArgumentError, "Unknown page '#{page}' for mission. Use index, new, edit, or designer."
      end
    end

    def mission_operation(context)
      operation = context.operation
      raise ArgumentError, "No current operation is available for missions." unless operation

      operation
    end
  end
end
