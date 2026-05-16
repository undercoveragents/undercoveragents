# frozen_string_literal: true

module SkillCatalogDesigner
  READ_SKILL_CATALOG_EDITABLE_FIELDS = [
    "name",
    "description",
  ].freeze

  class ReadSkillCatalogTool < RubyLLM::Tool
    include SkillCatalogLookup

    description "Inspect the current skill catalog or another skill catalog in the current operation."

    param :skill_catalog_id,
          desc: "Optional numeric ID or slug. Omit to inspect the current skill catalog from page context.",
          required: false

    def initialize(runtime_context:, current_skill_catalog: nil)
      super()
      @runtime_context = runtime_context
      @current_skill_catalog = current_skill_catalog
    end

    def name = "read_skill_catalog"

    def execute(skill_catalog_id: nil)
      skill_catalog = resolve_skill_catalog(skill_catalog_id)
      return missing_skill_catalog_message if skill_catalog.nil?

      [
        summary_section(skill_catalog),
        skills_section(skill_catalog),
        assigned_agents_section(skill_catalog),
        source_metadata_section(skill_catalog),
        editable_fields_section,
      ].join("\n\n")
    rescue ActiveRecord::RecordNotFound => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading skill catalog: #{e.message}"
    end

    private

    def summary_section(skill_catalog)
      [
        "## Skill Catalog",
        "- ID: `#{skill_catalog.id}`",
        "- Name: #{skill_catalog.name}",
        "- Slug: `#{skill_catalog.slug}`",
        "- Description: #{skill_catalog.description.presence || "None"}",
        "- Source type: `#{skill_catalog.source_type}`",
        "- Built-in: #{skill_catalog.builtin?}",
        ("- Built-in key: `#{skill_catalog.builtin_key}`" if skill_catalog.builtin_key.present?),
        "- Operation: #{skill_catalog.operation.name} (`#{skill_catalog.operation.slug}`)",
        "- Skill count: `#{skill_catalog.skill_count}`",
        "- Assigned agents: `#{skill_catalog.assigned_agents_count}`",
      ].compact.join("\n")
    end

    def skills_section(skill_catalog)
      skills = skill_catalog.skills.ordered.to_a
      return "## Skills\n- None" if skills.empty?

      lines = ["## Skills"]
      skills.each do |skill|
        lines << "- `#{skill.id}` — #{skill.name}"
      end
      lines.join("\n")
    end

    def assigned_agents_section(skill_catalog)
      assigned_agents = skill_catalog.assigned_agents.to_a
      return "## Assigned Agents\n- None" if assigned_agents.empty?

      lines = ["## Assigned Agents"]
      assigned_agents.each do |agent|
        lines << "- `#{agent.id}` — #{agent.name}"
      end
      lines.join("\n")
    end

    def source_metadata_section(skill_catalog)
      payload = skill_catalog.source_metadata.presence || {}
      "## Source Metadata\n```json\n#{JSON.pretty_generate(payload)}\n```"
    end

    def editable_fields_section
      [
        "## Editable Attribute Keys",
        *SkillCatalogDesigner::READ_SKILL_CATALOG_EDITABLE_FIELDS.map { |field| "- `#{field}`" },
        "- `source_type` and `source_metadata` are read-only in `manage_record`.",
        "- Use `manage_record` for skill catalog CRUD.",
        "- Use `read_skill`/`manage_skill` for individual skills.",
        "- Use `manage_skill_catalog_action` for import, restore, and agent assignment flows.",
      ].join("\n")
    end
  end
end
