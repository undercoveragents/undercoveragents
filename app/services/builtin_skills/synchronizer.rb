# frozen_string_literal: true

module BuiltinSkills
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
      @tenant = tenant
      @keys = Array(keys).compact.map(&:to_s).presence
      @restore = restore
    end

    def call
      definitions = load_definitions
      return Result.new(created_keys: [], restored_keys: []) if definitions.empty?

      headquarter = ensure_headquarter!
      created_keys, restored_keys = sync_definitions!(headquarter, definitions)

      Result.new(created_keys:, restored_keys:)
    end

    private

    def sync_definitions!(headquarter, definitions)
      created_keys = []
      restored_keys = []

      SkillCatalog.transaction do
        destroy_stale_catalogs!(headquarter, definitions) if @keys.blank?

        definitions.each do |definition|
          sync_catalog_definition!(headquarter, definition, created_keys, restored_keys)
        end
      end

      [created_keys, restored_keys]
    end

    def load_definitions
      definitions = BuiltinSkills::DefinitionLoader.load_all
      return definitions if @keys.blank?

      definitions_by_key = definitions.index_by(&:key)
      missing = @keys - definitions_by_key.keys
      raise "Unknown builtin skill catalog keys: #{missing.join(", ")}" if missing.any?

      @keys.map { |key| definitions_by_key.fetch(key) }
    end

    def ensure_headquarter!
      @tenant.ensure_core_resources!
      @tenant.headquarter_operation
    end

    def sync_catalog_definition!(headquarter, definition, created_keys, restored_keys)
      catalog = find_or_initialize_catalog(headquarter, definition)
      created = catalog.new_record?

      apply_locked_catalog_attributes(catalog, definition, headquarter)
      apply_editable_catalog_attributes(catalog, definition) if created || @restore
      catalog.save!

      sync_catalog_skills!(catalog, definition)
      track_result!(definition.key, created, created_keys, restored_keys)
    end

    def destroy_stale_catalogs!(headquarter, definitions)
      expected_keys = definitions.map(&:key)

      headquarter.skill_catalogs.builtin.find_each do |catalog|
        catalog.destroy! unless expected_keys.include?(catalog.builtin_key)
      end
    end

    def find_or_initialize_catalog(headquarter, definition)
      headquarter.skill_catalogs.builtin.find { |catalog| catalog.builtin_key == definition.key } ||
        headquarter.skill_catalogs.find_by(name: definition.name) ||
        headquarter.skill_catalogs.build
    end

    def apply_locked_catalog_attributes(catalog, definition, headquarter)
      catalog.operation = headquarter
      definition.locked_attributes.each do |attribute, value|
        catalog.public_send(:"#{attribute}=", value)
      end
    end

    def apply_editable_catalog_attributes(catalog, definition)
      catalog.assign_attributes(definition.editable_attributes)
    end

    def track_result!(key, created, created_keys, restored_keys)
      created_keys << key if created
      restored_keys << key if @restore && !created
    end

    def sync_catalog_skills!(catalog, definition)
      destroy_stale_skills!(catalog, definition.skills)

      definition.skills.each do |skill_definition|
        skill = find_or_initialize_skill(catalog, skill_definition)
        created = skill.new_record?

        apply_locked_skill_attributes(skill, skill_definition, definition.key)
        apply_editable_skill_attributes(skill, skill_definition) if created || @restore
        skill.save!
        sync_resources!(skill, skill_definition) if created || @restore
      end
    end

    def destroy_stale_skills!(catalog, skill_definitions)
      expected_keys = skill_definitions.map(&:key)

      catalog.skills.builtin.reorder(nil).find_each do |skill|
        skill.destroy! unless expected_keys.include?(skill.builtin_key)
      end
    end

    def find_or_initialize_skill(catalog, skill_definition)
      catalog.skills.builtin.find { |skill| skill.builtin_key == skill_definition.key } ||
        catalog.skills.find_by(name: skill_definition.name) ||
        catalog.skills.build
    end

    def apply_locked_skill_attributes(skill, skill_definition, catalog_key)
      skill_definition.locked_attributes(catalog_key:).each do |attribute, value|
        skill.public_send(:"#{attribute}=", value)
      end
    end

    def apply_editable_skill_attributes(skill, skill_definition)
      skill.assign_attributes(skill_definition.editable_attributes)
    end

    def sync_resources!(skill, skill_definition)
      skill.skill_resources.destroy_all

      skill_definition.resources.each do |relative_path, content|
        resource = skill.skill_resources.build(relative_path:)
        resource.file.attach(
          io: StringIO.new(content),
          filename: File.basename(relative_path),
          content_type: Marcel::MimeType.for(name: relative_path),
        )
        resource.save!
      end
    end
  end
end
