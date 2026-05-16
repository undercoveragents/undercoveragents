# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SqlToolInstructionsBuilder do
  describe ".call" do
    it "falls back to a generic SQL label when the connector is missing" do
      sql_query = build(
        :tools_sql_query,
        connector: nil,
        discovered_schema: {
          "objects" => [
            {
              "type" => "table",
              "name" => "users",
              "columns" => [{ "name" => "id", "type" => "integer", "nullable" => false }],
            },
          ],
        },
      )

      result = described_class.call(sql_query)

      expect(result).to include("read-only SQL database tool")
    end

    it "returns the default prompt when the discovered schema is not a hash" do
      sql_query = build(:tools_sql_query, discovered_schema: "invalid")

      expect(described_class.call(sql_query)).to eq(SqlQueryTool::DEFAULT_TOOL_PROMPT)
    end

    it "summarizes additional visible objects beyond the inline list limit" do
      sql_query = build(
        :tools_sql_query,
        connector: build(:connector, :sql_database, configuration: { "adapter_type" => "postgresql" }),
        discovered_schema: {
          "objects" => Array.new(9) do |index|
            {
              "type" => "table",
              "name" => "table_#{index}",
              "columns" => [{ "name" => "id", "type" => "integer", "nullable" => false }],
            }
          end,
        },
      )

      result = described_class.call(sql_query)

      expect(result).to include("plus 1 more")
    end
  end
end
