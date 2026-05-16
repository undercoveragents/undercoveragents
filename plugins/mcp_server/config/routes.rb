# frozen_string_literal: true

scope "/admin", as: :admin do
  get "connectors/transport_fields", to: "connector_mcp_server#transport_fields",
                                     as: :transport_fields_connectors

  post "connectors/mcp_server/test_connection",
       to: "connector_mcp_server#test_connection",
       as: :test_connection_mcp_server_connectors
end
