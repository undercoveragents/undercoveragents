# frozen_string_literal: true

module SkillCatalogDesigner
  module SkillCatalogLookup
    private

    def resolve_skill_catalog(skill_catalog_id)
      current_catalog = current_skill_catalog
      return current_catalog if skill_catalog_id.blank? && current_catalog.is_a?(SkillCatalog)

      identifier = skill_catalog_id.to_s.strip
      return nil if identifier.blank?

      scope = skill_catalog_scope
      scope.find_by(id: identifier) || scope.find_by(slug: identifier) ||
        unique_name_match(scope, identifier) || missing_skill_catalog!(identifier)
    end

    def unique_name_match(scope, identifier)
      matches = scope.where("LOWER(skill_catalogs.name) = ?", identifier.downcase).limit(2).to_a
      return matches.first if matches.one?
      return nil if matches.empty?

      raise ActiveRecord::RecordNotFound,
            "Multiple skill catalogs named '#{identifier}' were found. Pass the numeric ID or slug instead."
    end

    def current_skill_catalog
      return @current_skill_catalog if @current_skill_catalog.is_a?(SkillCatalog)

      object = @runtime_context&.ui_context&.dig("current_object")
      return current_skill_catalog_from_skill_object(object) if skill_object?(object)
      return unless skill_catalog_object?(object)

      scope = skill_catalog_scope
      scope.find_by(id: object["id"]) || scope.find_by(slug: object["slug"])
    end

    def skill_catalog_scope
      scope = SkillCatalog.includes(:operation)
      scope = scope.where(operation:) if operation
      scope = scope.joins(:operation).where(operations: { tenant_id: tenant.id }) if operation.nil? && tenant
      scope.ordered
    end

    def missing_skill_catalog_message
      "No current skill catalog is available. Pass skill_catalog_id after creating one or open a " \
        "skill catalog page first."
    end

    def missing_skill_catalog!(identifier)
      raise ActiveRecord::RecordNotFound, "Skill catalog '#{identifier}' was not found."
    end

    def skill_catalog_object?(object)
      object.is_a?(Hash) && [object["class_name"], object["type"]].compact.include?("SkillCatalog")
    end

    def skill_object?(object)
      object.is_a?(Hash) && [object["class_name"], object["type"]].compact.include?("Skill")
    end

    def current_skill_catalog_from_skill_object(object)
      skill = Skill.includes(:skill_catalog).find_by(id: object["id"])
      skill&.skill_catalog
    end

    def tenant
      @runtime_context&.tenant || @current_skill_catalog&.operation&.tenant || Current.tenant || Tenant.default_tenant
    end

    def operation
      @runtime_context&.operation || @current_skill_catalog&.operation
    end
  end
end
