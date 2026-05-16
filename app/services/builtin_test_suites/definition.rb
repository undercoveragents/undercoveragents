# frozen_string_literal: true

module BuiltinTestSuites
  class Definition
    attr_reader :key, :name, :description, :suite_type, :target_builtin_agent_key, :evaluation_temperature,
                :fixture_key, :test_cases, :source_path

    def initialize(**attributes)
      @key = attributes[:key].to_s
      @name = attributes[:name].to_s
      @description = attributes[:description].to_s
      @suite_type = attributes[:suite_type].to_s.presence || "agent"
      @target_builtin_agent_key = attributes[:target_builtin_agent_key].to_s.presence
      @evaluation_temperature = (attributes[:evaluation_temperature] || TestSuite::DEFAULT_TEMPERATURE).to_f
      @fixture_key = attributes[:fixture_key].to_s.presence
      @test_cases = Array(attributes[:test_cases])
      @source_path = Pathname.new(attributes[:source_path])
    end

    def locked_attributes
      {
        source_type: "builtin",
        source_metadata: {
          "builtin_key" => key,
          "builtin_source" => source_path.to_s,
          "target_builtin_agent_key" => target_builtin_agent_key,
        }.compact,
        suite_type:,
      }
    end

    def editable_attributes
      {
        name:,
        description:,
        evaluation_temperature:,
      }
    end
  end
end
