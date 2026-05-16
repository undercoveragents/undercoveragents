# frozen_string_literal: true

module SkillCatalogDesigner
  module SkillLookup
    private

    def resolve_skill(skill_id)
      current_record = current_skill
      return current_record if skill_id.blank? && current_record.is_a?(Skill)

      identifier = skill_id.to_s.strip
      return nil if identifier.blank?

      scope = skill_scope
      scope.find_by(id: identifier) || scope.find_by(name: identifier) || missing_skill!(identifier)
    end

    def current_skill
      return @current_skill if @current_skill.is_a?(Skill)

      object = @runtime_context&.ui_context&.dig("current_object")
      @current_skill = resolve_current_skill_object(object)
    end

    def skill_scope
      scope = Skill.includes(:skill_catalog)
      if operation
        scope = scope.joins(:skill_catalog).where(skill_catalogs: { operation_id: operation.id })
      elsif tenant
        scope = scope.joins(skill_catalog: :operation).where(operations: { tenant_id: tenant.id })
      end
      scope.ordered
    end

    def resolve_current_skill_object(object)
      return unless skill_object?(object)

      scope = skill_scope
      scope.find_by(id: object["id"])
    end

    def missing_skill_message
      "No current skill is available. Open a skill page first or pass skill_id."
    end

    def missing_skill!(identifier)
      raise ActiveRecord::RecordNotFound, "Skill '#{identifier}' was not found."
    end

    def skill_object?(object)
      object.is_a?(Hash) && [object["class_name"], object["type"]].compact.include?("Skill")
    end

    def tenant
      return @runtime_context.tenant if @runtime_context&.tenant

      current_skill_operation&.tenant || Current.tenant || Tenant.default_tenant
    end

    def operation
      @runtime_context&.operation || current_skill_operation
    end

    def current_skill_operation
      current_skill&.skill_catalog&.operation
    end
  end
end
