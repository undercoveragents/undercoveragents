# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SqlQuery do
  describe "#perform_discovery!" do
    let(:connector) { create(:connector, :sql_database) }
    let(:sql_query) { create(:tools_sql_query, connector:) }
    let(:schema) do
      {
        "objects" => [
          {
            "type" => "table",
            "name" => "users",
            "columns" => [
              { "name" => "id", "type" => "integer", "nullable" => false },
              { "name" => "account_id", "type" => "integer", "nullable" => false },
            ],
          },
          {
            "type" => "table",
            "name" => "accounts",
            "columns" => [
              { "name" => "id", "type" => "integer", "nullable" => false },
            ],
          },
        ],
      }
    end

    it "stores the schema, selects discovered objects, and generates instructions", :aggregate_failures do
      discovery_result = Tools::SchemaDiscoverer::Result.new(
        success?: true,
        schema:,
        message: "Discovered 2 objects",
      )

      allow(Tools::SchemaDiscoverer).to receive(:new).with(connector).and_return(
        instance_double(Tools::SchemaDiscoverer, call: discovery_result),
      )

      result = sql_query.perform_discovery!

      expect(result.success?).to be(true)
      expect(sql_query.reload.selected_object_names).to eq(["users", "accounts"])
      expect(sql_query.instructions).to include("read-only")
      expect(sql_query.instructions).to include("users")
      expect(sql_query.instructions).to include("accounts")
      expect(sql_query.instructions).to include("*_id")
    end
  end

  describe "#update_visibility!" do
    let(:sql_query) { create(:tools_sql_query, :with_schema, connector: create(:connector, :sql_database)) }

    it "refreshes instructions for the selected objects" do
      sql_query.update_visibility!(
        ActionController::Parameters.new(sql_query: { selected_objects: ["users"] }),
      )

      expect(sql_query.reload.selected_object_names).to eq(["users"])
      expect(sql_query.instructions).to include("users")
      expect(sql_query.instructions).not_to include("orders")
    end
  end

  describe "#effective_instructions" do
    it "builds deterministic instructions from discovered schema when custom instructions are blank" do
      sql_query = build(:tools_sql_query, :with_schema, instructions: nil, connector: create(:connector, :sql_database))

      expect(sql_query.effective_instructions).to include("read-only")
      expect(sql_query.effective_instructions).to include("users")
      expect(sql_query.effective_instructions).to include("orders")
    end
  end
end
