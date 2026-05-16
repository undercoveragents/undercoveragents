# frozen_string_literal: true

module SkillCatalogDesigner
  READ_SKILL_EDITABLE_FIELDS = [
    "name",
    "description",
    "instructions",
    "license",
    "compatibility",
    "allowed_tools",
    "metadata",
  ].freeze

  class ReadSkillTool < RubyLLM::Tool
    include SkillLookup

    description "Inspect the current skill or another skill in the current operation."

    param :skill_id,
          desc: "Optional numeric ID or exact skill name. Omit to inspect the current skill from page context.",
          required: false

    def initialize(runtime_context:, current_skill: nil)
      super()
      @runtime_context = runtime_context
      @current_skill = current_skill
    end

    def name = "read_skill"

    def execute(skill_id: nil)
      skill = resolve_skill(skill_id)
      return missing_skill_message if skill.nil?

      [
        summary_section(skill),
        metadata_section(skill),
        source_metadata_section(skill),
        resources_section(skill),
        editable_fields_section,
      ].join("\n\n")
    rescue ActiveRecord::RecordNotFound => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading skill: #{e.message}"
    end

    private

    def summary_section(skill)
      ["## Skill", *summary_lines(skill)].compact.join("\n")
    end

    def summary_lines(skill)
      [
        "- ID: `#{skill.id}`",
        "- Name: #{skill.name}",
        "- Catalog: #{skill.skill_catalog.name} (`#{skill.skill_catalog.id}`)",
        "- Description: #{skill.description.presence || "None"}",
        "- Source type: `#{skill.source_type}`",
        "- Built-in: #{skill.builtin?}",
        ("- Built-in key: `#{skill.builtin_key}`" if skill.builtin_key.present?),
        ("- License: #{skill.license}" if skill.license.present?),
        ("- Compatibility: #{skill.compatibility}" if skill.compatibility.present?),
        ("- Allowed tools: #{skill.allowed_tools}" if skill.allowed_tools.present?),
        "- Resource count: `#{skill.skill_resources.size}`",
      ]
    end

    def metadata_section(skill)
      "## Metadata\n```json\n#{JSON.pretty_generate(skill.metadata.presence || {})}\n```"
    end

    def source_metadata_section(skill)
      "## Source Metadata\n```json\n#{JSON.pretty_generate(skill.source_metadata.presence || {})}\n```"
    end

    def resources_section(skill)
      resources = skill.skill_resources.ordered.to_a
      return "## Resources\n- None" if resources.empty?

      lines = ["## Resources"]
      resources.each do |resource|
        lines << "- `#{resource.id}` — #{resource.relative_path} (`#{resource.resource_kind}`)"
      end
      lines.join("\n")
    end

    def editable_fields_section
      [
        "## Editable Attribute Keys",
        *READ_SKILL_EDITABLE_FIELDS.map { |field| "- `#{field}`" },
        "- Use `manage_skill` for create, update, delete, restore, and import.",
        "- `manage_skill` also supports `use_current_message_attachments`.",
        "- It also accepts `resource_directory` and `remove_resource_ids`.",
      ].join("\n")
    end
  end
end
