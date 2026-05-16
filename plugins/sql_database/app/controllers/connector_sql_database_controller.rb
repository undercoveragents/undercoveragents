# frozen_string_literal: true

class ConnectorSqlDatabaseController < Admin::BaseController
  def test_connection
    authorize Connector, :show?

    result = SqlDatabaseConnectionTester.new(sql_database_payload).call

    render json: { success: result.success?, message: result.message, details: result.details }
  rescue StandardError => e
    render json: { success: false, message: e.message, details: {} }, status: :internal_server_error
  end

  def database_options
    authorize Connector, :show?

    result = SqlDatabaseConnectionTester.new(sql_database_payload).available_databases
    databases = Array(result.details[:databases]).flatten.map { |database| database.to_s.strip }.compact_blank.uniq

    render json: { success: result.success?, message: result.message, databases: }
  rescue StandardError => e
    render json: { success: false, message: e.message, databases: [] }, status: :internal_server_error
  end

  private

  def sql_database_payload
    configurator = Connectors::SqlDatabase.new(Connectors::SqlDatabase.permitted_params(params))

    configurator.connection_test_params.merge(encrypted_password: configurator.encrypted_password)
  end
end
