# frozen_string_literal: true

class SkillActivationTool < RubyLLM::Tool
  description "Load the full SKILL.md instructions for an installed skill. " \
              "Use list_available_skills first if you need to inspect installed skill identifiers."

  param :skill_identifier,
        desc: "The skill identifier from the available_skills catalog.",
        type: :string

  def initialize(registry)
    super()
    @registry = registry
  end

  def name
    "activate_skill"
  end

  def execute(skill_identifier:)
    entry = @registry.find(skill_identifier)
    unless entry
      return "The selected skill could not be found. Call list_available_skills to inspect installed skill identifiers."
    end

    markdown = entry.skill.skill_markdown
    resources = entry.skill.skill_resources.ordered.pluck(:relative_path)

    <<~CONTENT.strip
      <skill_content identifier="#{ERB::Util.h(entry.identifier)}" name="#{ERB::Util.h(entry.skill.name)}" catalog="#{ERB::Util.h(entry.catalog.name)}">
      #{markdown}

      Skill identifier: #{entry.identifier}
      Relative paths are rooted at this skill. Use read_skill_resource to load any referenced file.
      #{resource_listing(resources)}
      </skill_content>
    CONTENT
  end

  private

  def resource_listing(resources)
    return "" if resources.empty?

    [
      "<skill_resources>",
      resources.map { |path| "  <file>#{ERB::Util.h(path)}</file>" },
      "</skill_resources>",
    ].flatten.join("\n")
  end
end
