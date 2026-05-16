# frozen_string_literal: true

module Skills
  class AssignedRegistry
    Entry = Data.define(:identifier, :catalog, :skill)
    CatalogEntry = Data.define(:identifier, :catalog, :skills)

    delegate :any?, to: :catalog_entries
    def initialize(agent)
      @agent = agent
    end

    def any_resources?
      entries.any? { |entry| entry.skill.skill_resources.any? }
    end

    def entries
      @entries ||= build_entries
    end

    def catalog_entries
      @catalog_entries ||= build_catalog_entries
    end

    def find(identifier)
      entries.find { |entry| entry.identifier == identifier.to_s }
    end

    private

    attr_reader :agent

    def build_catalog_entries
      agent.skill_catalogs.includes(skills: :skill_resources).ordered.map do |catalog|
        CatalogEntry.new(
          identifier: catalog_identifier(catalog),
          catalog:,
          skills: catalog.skills.to_a,
        )
      end
    end

    def build_entries
      catalog_entries.flat_map do |catalog_entry|
        catalog_entry.skills.map do |skill|
          Entry.new(
            identifier: skill.skill_identifier,
            catalog: catalog_entry.catalog,
            skill:,
          )
        end
      end
    end

    def catalog_identifier(catalog)
      catalog.builtin_key.presence || catalog.slug
    end
  end
end
