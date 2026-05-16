# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ConnectorSqlDatabaseController" do
  describe "POST /connectors/sql_database/test_connection" do
    let(:success_result) do
      BaseConnectionTester::Result.new(
        success?: true,
        message: "Connected successfully",
        details: { version: "PostgreSQL 16.0" },
      )
    end

    let(:failure_result) do
      BaseConnectionTester::Result.new(
        success?: false,
        message: "Connection refused",
        details: {},
      )
    end

    before do
      allow(SqlDatabaseConnectionTester).to receive(:new).and_return(
        instance_double(SqlDatabaseConnectionTester, call: success_result),
      )
    end

    it "returns a successful JSON response when connection succeeds" do
      post "/admin/connectors/sql_database/test_connection", params: {
        sql_database: { adapter_type: "postgresql", host: "localhost", database_name: "test_db" },
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(response.parsed_body["message"]).to eq("Connected successfully")
    end

    it "returns a failure JSON response when connection fails" do
      allow(SqlDatabaseConnectionTester).to receive(:new).and_return(
        instance_double(SqlDatabaseConnectionTester, call: failure_result),
      )

      post "/admin/connectors/sql_database/test_connection", params: {
        sql_database: { adapter_type: "postgresql", host: "badhost", database_name: "nope" },
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to eq("Connection refused")
    end

    it "returns 500 when an unexpected error occurs" do
      allow(SqlDatabaseConnectionTester).to receive(:new).and_raise(StandardError.new("unexpected"))

      post "/admin/connectors/sql_database/test_connection", params: {
        sql_database: { adapter_type: "postgresql", host: "localhost", database_name: "test_db" },
      }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to eq("unexpected")
    end
  end

  describe "POST /connectors/sql_database/database_options" do
    let(:database_result) do
      BaseConnectionTester::Result.new(
        success?: true,
        message: "Loaded 3 databases",
        details: { databases: ["analytics", "postgres", "warehouse"] },
      )
    end

    it "returns discovered database names" do
      allow(SqlDatabaseConnectionTester).to receive(:new).and_return(
        instance_double(SqlDatabaseConnectionTester, available_databases: database_result),
      )

      post "/admin/connectors/sql_database/database_options", params: {
        sql_database: { adapter_type: "postgresql", host: "localhost", username: "postgres" },
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(response.parsed_body["databases"]).to eq(["analytics", "postgres", "warehouse"])
    end

    it "returns 500 when database discovery raises unexpectedly" do
      allow(SqlDatabaseConnectionTester).to receive(:new).and_raise(StandardError.new("boom"))

      post "/admin/connectors/sql_database/database_options", params: {
        sql_database: { adapter_type: "postgresql", host: "localhost" },
      }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to eq("boom")
    end
  end
end
