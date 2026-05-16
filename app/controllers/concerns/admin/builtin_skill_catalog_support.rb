# frozen_string_literal: true

module Admin
  module BuiltinSkillCatalogSupport
    private

    def restored_builtin_catalog(builtin_key)
      current_tenant
        .headquarter_operation
        .skill_catalogs
        .builtin
        .where("source_metadata ->> 'builtin_key' = ?", builtin_key)
        .first!
    end

    def ensure_builtin_skill_catalogs!
      BuiltinSkills::Synchronizer.ensure_present!(tenant: current_tenant)
    end

    def headquarter_operation?
      current_operation&.headquarter?
    end
  end
end
