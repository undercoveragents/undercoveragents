class CreateConnectorsLlmProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors_llm_providers do |t|
      # Provider identification
      t.string :provider, null: false

      # Provider-specific credentials
      t.string :api_key
      t.string :api_base
      t.string :organization_id
      t.string :project_id
      t.string :secret_key
      t.string :region
      t.string :session_token
      t.string :auth_token

      # Provider-specific options
      t.boolean :use_system_role, default: false, null: false

      # Connection settings (advanced)
      t.string :http_proxy
      t.integer :request_timeout, default: 120, null: false
      t.integer :max_retries, default: 3, null: false
      t.float :retry_interval, default: 0.1, null: false
      t.integer :retry_backoff_factor, default: 2, null: false
      t.float :retry_interval_randomness, default: 0.5, null: false

      t.timestamps
    end
  end
end
