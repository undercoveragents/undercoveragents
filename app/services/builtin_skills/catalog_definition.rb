# frozen_string_literal: true

module BuiltinSkills
  class CatalogDefinition
    attr_reader :key, :name, :description, :skills, :source_path

    def initialize(key:, name:, description:, skills:, source_path:)
      @key = key.to_s
      @name = name.to_s
      @description = description.to_s
      @skills = Array(skills)
      @source_path = Pathname.new(source_path)
    end

    def editable_attributes
      {
        name:,
        description:,
      }
    end

    def locked_attributes
      {
        source_type: "builtin",
        source_metadata: {
          "builtin_key" => key,
          "builtin_source" => source_path.to_s,
        },
      }
    end
  end
end
