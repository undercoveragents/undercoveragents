# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SqlSchemaBuilder do
  describe ".call" do
    let(:sql_database) { build(:connector, :sql_database) }
    let(:sql_query) do
      build(:tools_sql_query,
            connector: sql_database,
            discovered_schema:,
            selected_objects:,)
    end

    context "when no schema is discovered" do
      let(:discovered_schema) { {} }
      let(:selected_objects) { [] }

      it "returns a no-schema message" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to eq("No schema information available.")
      end

      it "returns no-schema when called with only sql_database (no sql_query)" do
        result = described_class.call(sql_database)

        expect(result).to eq("No schema information available.")
      end
    end

    context "when schema has objects but no selection" do
      let(:discovered_schema) do
        {
          "objects" => [
            {
              "type" => "table",
              "name" => "users",
              "columns" => [
                { "name" => "id", "type" => "integer", "nullable" => false, "default" => nil },
                { "name" => "email", "type" => "character varying", "nullable" => false, "default" => nil },
                { "name" => "name", "type" => "character varying", "nullable" => true, "default" => nil },
              ],
            },
            {
              "type" => "table",
              "name" => "orders",
              "columns" => [
                { "name" => "id", "type" => "integer", "nullable" => false },
                { "name" => "user_id", "type" => "integer", "nullable" => false },
                { "name" => "total", "type" => "numeric", "nullable" => true },
              ],
            },
          ],
        }
      end
      let(:selected_objects) { [] }

      it "includes all discovered objects" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to include("users (table)")
        expect(result).to include("orders (table)")
      end

      it "includes column details" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to include("id : integer")
        expect(result).to include("email : character varying")
        expect(result).to include("NOT NULL")
      end

      it "includes a schema header" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to start_with("SCHEMA")
      end

      it "infers relationships from _id columns" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to include("orders.user_id -> users.id")
      end
    end

    context "when selected_objects filters objects" do
      let(:discovered_schema) do
        {
          "objects" => [
            { "type" => "table", "name" => "users",
              "columns" => [{ "name" => "id", "type" => "integer", "nullable" => false }], },
            { "type" => "table", "name" => "orders",
              "columns" => [{ "name" => "id", "type" => "integer", "nullable" => false }], },
            { "type" => "view", "name" => "reports",
              "columns" => [{ "name" => "id", "type" => "integer", "nullable" => false }], },
          ],
        }
      end
      let(:selected_objects) { [{ "name" => "users" }, { "name" => "orders" }] }

      it "only includes selected objects" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to include("users (table)")
        expect(result).to include("orders (table)")
        expect(result).not_to include("reports")
      end
    end

    context "when columns have defaults" do
      let(:discovered_schema) do
        {
          "objects" => [
            {
              "type" => "table",
              "name" => "settings",
              "columns" => [
                { "name" => "active", "type" => "boolean", "nullable" => false, "default" => "true" },
              ],
            },
          ],
        }
      end
      let(:selected_objects) { [] }

      it "includes default values in schema text" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to include("DEFAULT true")
      end
    end

    context "with no relationships detected" do
      let(:discovered_schema) do
        {
          "objects" => [
            { "type" => "table", "name" => "settings",
              "columns" => [{ "name" => "key", "type" => "text", "nullable" => false }], },
          ],
        }
      end
      let(:selected_objects) { [] }

      it "shows no-relationships message" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to include("No relationships detected.")
      end
    end

    context "when object has no columns" do
      let(:discovered_schema) do
        {
          "objects" => [
            { "type" => "view", "name" => "summary_view", "columns" => [] },
          ],
        }
      end
      let(:selected_objects) { [] }

      it "includes the object without column details" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to include("summary_view (view)")
        expect(result).not_to include("Columns:")
      end
    end

    context "when discovered_schema is not a hash" do
      let(:discovered_schema) { "invalid" }
      let(:selected_objects) { [] }

      it "returns no-schema message" do
        result = described_class.call(sql_database, sql_query:)

        expect(result).to eq("No schema information available.")
      end
    end
  end
end
