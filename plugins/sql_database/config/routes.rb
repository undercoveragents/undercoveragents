# frozen_string_literal: true

scope "/admin", as: :admin do
  post "connectors/sql_database/database_options",
       to: "connector_sql_database#database_options",
       as: :database_options_sql_database_connectors

  post "connectors/sql_database/test_connection",
       to: "connector_sql_database#test_connection",
       as: :test_connection_sql_database_connectors
end
