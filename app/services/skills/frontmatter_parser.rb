# frozen_string_literal: true

module Skills
  class FrontmatterParser
    Result = Data.define(:attributes, :warnings, :error_message) do
      def success?
        error_message.blank?
      end
    end

    FRONTMATTER_PATTERN = /\A---\s*\n(?<yaml>.*?)\n---\s*\n?(?<body>.*)\z/m

    def parse(content, directory_name: nil)
      match = extract_frontmatter(content)
      return match if match.is_a?(Result)

      data = parsed_frontmatter(match[:yaml])
      return data if data.is_a?(Result)

      build_result(match:, data:, directory_name:)
    end

    private

    def extract_frontmatter(content)
      FRONTMATTER_PATTERN.match(content.to_s) || failure("SKILL.md must start with YAML frontmatter.")
    end

    def parsed_frontmatter(yaml_source)
      data = load_yaml(yaml_source)
      return data if data.is_a?(Hash)

      failure("The SKILL.md frontmatter could not be parsed.")
    end

    def build_result(match:, data:, directory_name:)
      name = resolved_name(data, directory_name)
      description = data["description"].to_s.strip
      return failure("Every skill must include a name.") if name.blank?
      return failure("Every skill must include a non-empty description.") if description.blank?

      Result.new(
        attributes: build_attributes(match:, data:, name:, description:, directory_name:),
        warnings: build_warnings(data:, name:, description:, directory_name:),
        error_message: nil,
      )
    end

    def resolved_name(data, directory_name)
      data["name"].to_s.strip.presence || directory_name.to_s.strip.presence
    end

    def build_attributes(match:, data:, name:, description:, directory_name:)
      {
        name:,
        description:,
        instructions: match[:body].to_s.rstrip,
        license: data["license"].to_s.strip.presence,
        compatibility: data["compatibility"].to_s.strip.presence,
        allowed_tools: data["allowed-tools"].to_s.strip.presence,
        metadata: normalize_metadata(data["metadata"]),
        source_metadata: { "directory_name" => directory_name.presence },
      }
    end

    def build_warnings(data:, name:, description:, directory_name:)
      warnings = SpecificationValidator.new(
        name:,
        description:,
        compatibility: data["compatibility"],
        directory_name:,
      ).warnings
      if data["name"].blank? && directory_name.present?
        warnings.unshift("The skill name was inferred from the directory name.")
      end
      warnings
    end

    def load_yaml(yaml_source)
      parse_yaml_source(yaml_source) || parse_yaml_source(quote_common_colon_values(yaml_source))
    end

    def parse_yaml_source(yaml_source)
      YAML.safe_load(yaml_source, aliases: true) || {}
    rescue Psych::SyntaxError
      nil
    end

    def quote_common_colon_values(yaml_source)
      yaml_source.lines.map do |line|
        next line unless line.match?(/\A[[:word:]-]+:\s*.+:.+/)

        key, raw_value = line.split(":", 2)
        value = raw_value.to_s.strip
        next line if value.blank? || value.start_with?("\"", "'", "{", "[", "|", ">")

        "#{key}: #{value.to_json}\n"
      end.join
    end

    def normalize_metadata(value)
      return {} unless value.is_a?(Hash)

      value.deep_stringify_keys
    end

    def failure(message)
      Result.new(attributes: {}, warnings: [], error_message: message)
    end
  end
end
