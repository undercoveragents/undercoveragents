# frozen_string_literal: true

class SkillListTool < RubyLLM::Tool
  description(
    "List built-in skill manuals and identifiers available to the current agent. " \
    "Do not use this for tenant or workspace record inventory such as configured skill catalogs, tools, " \
    "agents, or channels.",
  )

  param :catalog,
        desc: "Optional catalog name, id, slug, or builtin key to filter by.",
        type: :string,
        required: false

  param :query,
        desc: "Optional text to match against skill names, catalogs, or descriptions.",
        type: :string,
        required: false

  def initialize(registry)
    super()
    @registry = registry
  end

  def name
    "list_available_skills"
  end

  def execute(catalog: nil, query: nil)
    entries = filtered_entries(catalog:, query:)
    return no_matches_response if entries.empty?

    <<~CONTENT.strip
      Installed skill catalogs: #{entries.map { |entry| entry.catalog.id }.uniq.count}
      Installed skills: #{entries.size}
      Call activate_skill with a skill identifier to load the full SKILL.md instructions.

      <available_skills>
      #{skill_entries_xml(entries)}
      </available_skills>
    CONTENT
  end

  private

  attr_reader :registry

  def filtered_entries(catalog:, query:)
    registry.entries.select do |entry|
      matches_catalog?(entry, catalog) && matches_query?(entry, query)
    end
  end

  def matches_catalog?(entry, catalog)
    return true if catalog.blank?

    normalized_catalog = catalog.to_s.strip.downcase
    catalog_match_values(entry.catalog).any? { |value| value.to_s.downcase == normalized_catalog }
  end

  def matches_query?(entry, query)
    return true if query.blank?

    needle = query.to_s.strip.downcase
    haystacks = [entry.skill.name, entry.catalog.name, entry.skill.description, entry.identifier]
    haystacks.any? { |value| value.to_s.downcase.include?(needle) }
  end

  def no_matches_response
    <<~CONTENT.strip
      No installed skills matched the requested filters.
      Call list_available_skills without filters to browse every installed skill, or pass a catalog identifier from available_skill_catalogs.
    CONTENT
  end

  def catalog_match_values(catalog)
    [catalog.id, catalog.name, catalog.slug, catalog.builtin_key]
  end

  def skill_entries_xml(entries)
    entries.map do |entry|
      <<~XML.strip
        <skill>
          <identifier>#{ERB::Util.h(entry.identifier)}</identifier>
          <name>#{ERB::Util.h(entry.skill.name)}</name>
          <catalog>#{ERB::Util.h(entry.catalog.name)}</catalog>
          <description>#{ERB::Util.h(entry.skill.description)}</description>
          <has_resources>#{entry.skill.skill_resources.any?}</has_resources>
        </skill>
      XML
    end.join("\n")
  end
end
