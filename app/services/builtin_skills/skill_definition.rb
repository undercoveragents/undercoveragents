# frozen_string_literal: true

module BuiltinSkills
  class SkillDefinition
    attr_reader :key, :name, :description, :instructions, :license,
                :compatibility, :allowed_tools, :metadata, :resources, :source_path

    def initialize(key:, source_path:, **attributes)
      @key = key.to_s
      @name = attributes.fetch(:name).to_s
      @description = attributes.fetch(:description).to_s
      @instructions = attributes.fetch(:instructions).to_s
      @license = attributes[:license].presence
      @compatibility = attributes[:compatibility].presence
      @allowed_tools = attributes[:allowed_tools].presence
      @metadata = attributes.fetch(:metadata).deep_stringify_keys
      @resources = attributes.fetch(:resources).transform_keys(&:to_s)
      @source_path = Pathname.new(source_path)
    end

    def editable_attributes
      {
        name:,
        description:,
        instructions:,
        license:,
        compatibility:,
        allowed_tools:,
        metadata:,
      }
    end

    def locked_attributes(catalog_key:)
      {
        source_type: "builtin",
        source_metadata: {
          "builtin_key" => key,
          "builtin_catalog_key" => catalog_key,
          "builtin_source" => source_path.to_s,
        },
      }
    end
  end
end
