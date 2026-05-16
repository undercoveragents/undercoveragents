# frozen_string_literal: true

# Builds a Tools::McpServer JSONB configurator (ActiveModel, not AR).
# `create` also generates a backing Tool AR record with _tool_record set.
FactoryBot.define do
  factory :tools_mcp_server, class: "Tools::McpServer" do
    skip_create

    transient do
      tool_name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    end

    connector factory: [:connector, :mcp_server]
    discovered_tools { [] }
    selected_tools { [] }

    initialize_with { new(attributes.except(:tool_name)) }

    after(:create) do |mcp, evaluator|
      tool = Tool.new(
        tool_type: "mcp_server",
        name: evaluator.tool_name,
        operation: OperationFactoryHelper.default_operation,
      )
      tool.configurator = mcp
      tool.save!
      mcp._tool_record = tool
    end

    trait :with_tools do
      discovered_tools do
        [
          { "name" => "read_file", "description" => "Read a file from the filesystem" },
          { "name" => "list_directory", "description" => "List contents of a directory" },
          { "name" => "search_files", "description" => "Search for files matching a pattern" },
        ]
      end
      selected_tools do
        [
          { "name" => "read_file" },
          { "name" => "list_directory" },
          { "name" => "search_files" },
        ]
      end
      tools_discovered_at { Time.current }
    end

    trait :with_partial_selection do
      discovered_tools do
        [
          { "name" => "read_file", "description" => "Read a file from the filesystem" },
          { "name" => "list_directory", "description" => "List contents of a directory" },
          { "name" => "search_files", "description" => "Search for files matching a pattern" },
        ]
      end
      selected_tools do
        [
          { "name" => "read_file" },
        ]
      end
      tools_discovered_at { Time.current }
    end
  end
end
