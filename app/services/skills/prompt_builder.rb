# frozen_string_literal: true

module Skills
  class PromptBuilder
    include ERB::Util

    def initialize(registry)
      @registry = registry
    end

    def build
      return nil unless registry.any?

      <<~PROMPT.strip
        The following skill catalogs provide specialized instructions for specific task areas.
        Call list_available_skills with a catalog identifier when you need to inspect which skills a catalog contains.
        When a listed skill is relevant, call activate_skill with the skill identifier to load the full SKILL.md instructions.
        If an activated skill references bundled files, call read_skill_resource with the same skill identifier and the listed relative path.

        <available_skill_catalogs>
        #{catalog_entries_xml}
        </available_skill_catalogs>
      PROMPT
    end

    private

    attr_reader :registry

    def catalog_entries_xml
      registry.catalog_entries.map do |entry|
        <<~XML.strip
          <catalog>
            <identifier>#{h(entry.identifier)}</identifier>
            <name>#{h(entry.catalog.name)}</name>
            <description>#{h(entry.catalog.description)}</description>
            <skill_count>#{entry.skills.size}</skill_count>
          </catalog>
        XML
      end.join("\n")
    end
  end
end
