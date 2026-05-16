# frozen_string_literal: true

module Skills
  class MarkdownBuilder
    def initialize(skill)
      @skill = skill
    end

    def build
      <<~MARKDOWN.strip
        ---
        #{frontmatter_yaml}
        ---

        #{skill.instructions.to_s.rstrip}
      MARKDOWN
    end

    private

    attr_reader :skill

    def frontmatter_yaml
      frontmatter.to_yaml.delete_prefix("---\n").rstrip
    end

    def frontmatter
      {
        "name" => skill.name,
        "description" => skill.description,
        "license" => skill.license.presence,
        "compatibility" => skill.compatibility.presence,
        "metadata" => skill.metadata.presence,
        "allowed-tools" => skill.allowed_tools.presence,
      }.compact
    end
  end
end
