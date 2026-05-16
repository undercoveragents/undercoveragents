# frozen_string_literal: true

class ConnectorMcpServerController < Admin::BaseController
  def transport_fields
    authorize Connector, :transport_fields?
    connector = Connectors::McpServer.new(transport_type: params[:transport_type])
    prepend_view_path(connector.form_partial_path)
    lookup_context.prefixes = [""]
    render partial: "mcp_server_transport_fields",
           locals: { connector: }, layout: false
  end

  def test_connection
    authorize Connector, :show?

    configurator = Connectors::McpServer.new(Connectors::McpServer.permitted_params(params))
    result = McpServerConnectionTester.new(configurator.connection_test_params).call

    render json: { success: result.success?, message: result.message, details: result.details }
  rescue StandardError => e
    render json: { success: false, message: e.message, details: {} }, status: :internal_server_error
  end
end
