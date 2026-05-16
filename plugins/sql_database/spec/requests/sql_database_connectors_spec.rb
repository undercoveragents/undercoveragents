# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SQL Database Connectors" do
  describe "GET /connectors/new" do
    it "shows the SQL connector wizard form" do
      get new_admin_connector_path(type: "sql_database")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create a SQL connector")
      expect(response.body).to include("Database Type")
      expect(response.body).to include("Load Databases")
      expect(response.body).to include("Leave blank for the adapter default port.")
    end

    it "hides unsupported SQL connector adapters" do
      get new_admin_connector_path(type: "sql_database")

      expect(response.body).not_to include("SQL Server")
      expect(response.body).not_to include("Oracle")
    end

    it "bootstraps plugin stylesheets for turbo-frame navigation" do
      get new_admin_connector_path(type: "sql_database"), headers: { "Turbo-Frame" => "app-content-frame" }

      document = response.parsed_body
      container = document.at_css(".connector-form-container[data-sql-database-wizard-styles-urls-value]")
      stylesheet_urls = JSON.parse(container["data-sql-database-wizard-styles-urls-value"])

      expect(container["data-controller"]).to include("sql-database-wizard-styles")
      expect(stylesheet_urls).to include(a_string_matching(/plugin_sql_database_wizard/))
      expect(stylesheet_urls).to include(a_string_matching(/plugin_sql_database_connector_wizard/))
    end
  end

  describe "POST /connectors" do
    let(:valid_params) do
      {
        connector_type: "sql_database",
        connector: { name: "My SQL DB", description: "Test database" },
        sql_database: {
          adapter_type: "postgresql",
          host: "localhost",
          port: 5432,
          database_name: "test_db",
          schema_name: "public",
          username: "user",
          pool_size: 5,
          timeout: 5000,
          max_results: 100,
          read_only: true,
        },
      }
    end

    it "creates a new SQL connector" do
      expect { post admin_connectors_path, params: valid_params }
        .to change(Connector, :count).by(1)
        .and change(Connectors::SqlDatabase, :count).by(1)
    end

    it "redirects to the connector show page" do
      post admin_connectors_path, params: valid_params

      expect(response).to redirect_to(admin_connector_path(Connector.last))
    end

    it "renders the new page with errors for invalid params" do
      post admin_connectors_path, params: {
        connector_type: "sql_database",
        connector: { name: "" },
        sql_database: { adapter_type: "postgresql", host: "" },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /connectors/:id" do
    let(:connector) { create(:connector, :sql_database, name: "Test DB") }

    it "returns a successful response" do
      get admin_connector_path(connector)

      expect(response).to have_http_status(:ok)
    end

    it "displays the connector details" do
      get admin_connector_path(connector)

      expect(response.body).to include("Test DB")
      expect(response.body).to include("SQL Database")
      expect(response.body).to include("Edit")
    end

    it "shows delete and omits the old connector actions" do
      get admin_connector_path(connector)

      expect(response.body).to include("Delete Connector")
      expect(response.body).not_to include("Edit Connection")
      expect(response.body).not_to include(toggle_admin_connector_path(connector))
    end
  end

  describe "GET /connectors/:id/edit" do
    let(:connector) { create(:connector, :sql_database, name: "Test DB") }

    it "returns a successful response" do
      get edit_admin_connector_path(connector)

      expect(response).to have_http_status(:ok)
    end

    it "displays the SQL connector wizard" do
      get edit_admin_connector_path(connector)

      expect(response.body).to include("Test DB")
      expect(response.body).to include("Refine connector settings")
      expect(response.body).to include("Load Databases")
    end

    it "renders manual database entry for a MySQL connector" do
      mysql_connector = create(:connector, :sql_database, name: "MySQL DB", adapter_type: "mysql")

      get edit_admin_connector_path(mysql_connector)

      expect(response.body).to include("Enter the database name directly for MySQL connections.")
      expect(response.body).not_to include("Load the server catalog to populate the database dropdown.")
    end

    it "defaults to connection string mode when the connector uses a connection string" do
      connector = create(
        :connector,
        :sql_database,
        connection_string: "postgresql://localhost:5432/test_db",
      )

      get edit_admin_connector_path(connector)

      document = response.parsed_body
      connection_string_option = document.at_css(
        'input[name="sql_database_connection_mode"][value="connection_string"]',
      )

      expect(connection_string_option["checked"]).to eq("checked")
    end
  end

  describe "PATCH /connectors/:id" do
    let(:connector) { create(:connector, :sql_database, name: "Old Name") }

    it "updates connection settings" do
      patch admin_connector_path(connector), params: {
        connector_type: "sql_database",
        connector: { name: "New Name" },
        sql_database: { host: "newhost", database_name: "newdb" },
      }

      expect(response).to redirect_to(admin_connector_path(connector.reload))
      expect(connector.name).to eq("New Name")
    end

    it "re-renders the edit form for invalid params" do
      patch admin_connector_path(connector), params: {
        connector_type: "sql_database",
        connector: { name: "" },
        sql_database: { host: "newhost" },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "infers connector type from the existing record when connector_type is absent" do
      patch admin_connector_path(connector), params: {
        connector: { name: "Inferred Name" },
        sql_database: { host: "newhost", database_name: "newdb" },
      }

      expect(response).to redirect_to(admin_connector_path(connector.reload))
      expect(connector.name).to eq("Inferred Name")
    end
  end
end
