# frozen_string_literal: true

# Builds a Tools::SqlQuery JSONB configurator (ActiveModel, not AR).
# `create` also generates a backing Tool AR record with _tool_record set.
FactoryBot.define do
  factory :tools_sql_query, class: "Tools::SqlQuery" do
    skip_create

    transient do
      tool_name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    end

    connector factory: [:connector, :sql_database]
    instructions { nil }
    discovered_schema { {} }
    selected_objects { [] }
    llm_config_source { "inherit" }

    initialize_with { new(attributes.except(:tool_name)) }

    after(:create) do |sq, evaluator|
      tool = Tool.new(
        tool_type: "sql_query",
        name: evaluator.tool_name,
        operation: OperationFactoryHelper.default_operation,
      )
      tool.configurator = sq
      tool.save!
      sq._tool_record = tool
    end

    trait :with_schema do
      discovered_schema do
        {
          "objects" => [
            {
              "type" => "table",
              "name" => "users",
              "columns" => [
                { "name" => "id", "type" => "integer", "nullable" => false },
                { "name" => "name", "type" => "character varying", "nullable" => false },
              ],
            },
            {
              "type" => "table",
              "name" => "orders",
              "columns" => [
                { "name" => "id", "type" => "integer", "nullable" => false },
                { "name" => "total", "type" => "numeric", "nullable" => true },
              ],
            },
          ],
        }
      end
      schema_discovered_at { Time.current }
      selected_objects { [{ "name" => "users" }, { "name" => "orders" }] }
    end

    trait :with_custom_llm do
      llm_config_source { "custom" }
      llm_connector factory: [:connector, :llm_provider, :enabled]
      model_id { "gpt-4.1-mini" }
      temperature { 0.1 }
    end
  end
end
