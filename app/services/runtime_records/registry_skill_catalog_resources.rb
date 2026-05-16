# frozen_string_literal: true

module RuntimeRecords
  module RegistrySkillCatalogResources
    private

    def register_skill_catalog
      register(
        "skill_catalog",
        label: "Skill Catalog",
        model_class: SkillCatalog,
        permitted_attributes: ["name", "description"],
        scope_resolver: method(:skill_catalog_scope),
        base_attributes: method(:skill_catalog_base_attributes),
        default_page: "show",
        page_resolver: method(:skill_catalog_page_path),
        create_handler: nil,
        update_handler: nil,
      )
    end

    def skill_catalog_scope(context)
      operation = skill_catalog_operation(context)

      tenant_scope = SkillCatalog.joins(:operation)
      tenant_scope = tenant_scope.where(operations: { tenant_id: context.tenant.id }) if context.tenant
      tenant_scope.where(operation:)
    end

    def skill_catalog_base_attributes(context)
      operation = skill_catalog_operation(context)
      if context.tenant && operation.tenant_id != context.tenant.id
        raise ArgumentError, "The current operation is outside the active tenant."
      end

      { operation: }
    end

    def skill_catalog_page_path(page, record:, context:)
      _context = context
      helpers = Rails.application.routes.url_helpers

      case page.to_s
      when "index"
        helpers.admin_skill_catalogs_path
      when "new"
        helpers.new_admin_skill_catalog_path
      when "show"
        raise ArgumentError, "Skill catalog page 'show' requires a record." unless record

        helpers.admin_skill_catalog_path(record)
      when "edit"
        raise ArgumentError, "Skill catalog page 'edit' requires a record." unless record

        helpers.edit_admin_skill_catalog_path(record)
      else
        raise ArgumentError, "Unknown page '#{page}' for skill catalog. Use index, new, show, or edit."
      end
    end

    def skill_catalog_operation(context)
      operation = context.operation
      raise ArgumentError, "No current operation is available for skill catalogs." unless operation

      operation
    end
  end
end
