# frozen_string_literal: true

# Builds a Tools::MissionTool JSONB configurator (ActiveModel, not AR).
# `create` also generates a backing Tool AR record with _tool_record set.
FactoryBot.define do
  factory :tools_mission_tool, class: "Tools::MissionTool" do
    skip_create

    transient do
      tool_name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    end

    mission

    initialize_with { new(attributes.except(:tool_name)) }

    after(:create) do |mt, evaluator|
      tool = Tool.new(
        tool_type: "mission_tool",
        name: evaluator.tool_name,
        operation: OperationFactoryHelper.default_operation,
      )
      tool.configurator = mt
      tool.save!
      mt._tool_record = tool
    end

    trait :with_input_fields do
      mission do
        association :mission, flow_data: {
          "nodes" => [
            {
              "id" => "input_1",
              "type" => "input",
              "data" => {
                "fields" => [
                  { "variable_name" => "username", "field_type" => "string", "required" => true },
                  { "variable_name" => "limit", "field_type" => "number", "required" => false },
                ],
              },
            },
            {
              "id" => "output_1",
              "type" => "output",
              "data" => {
                "status" => "success",
                "selected_variables" => ["result"],
              },
            },
          ],
          "edges" => [],
        }
      end
    end
  end
end
