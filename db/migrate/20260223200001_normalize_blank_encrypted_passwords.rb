# frozen_string_literal: true

class NormalizeBlankEncryptedPasswords < ActiveRecord::Migration[8.1]
  # Empty strings in encrypts-declared columns cause ActiveRecord::Encryption::Errors::Decryption
  # at read time. NULL is safe — Rails skips decryption for nil values.
  def up
    execute "UPDATE connectors_sql_databases SET encrypted_password = NULL WHERE encrypted_password = ''"
    execute "UPDATE connectors_vector_databases SET encrypted_password = NULL WHERE encrypted_password = ''"
    execute "UPDATE connectors_llm_providers SET api_key = NULL WHERE api_key = ''"
    execute "UPDATE connectors_llm_providers SET auth_token = NULL WHERE auth_token = ''"
    execute "UPDATE connectors_llm_providers SET secret_key = NULL WHERE secret_key = ''"
    execute "UPDATE connectors_llm_providers SET session_token = NULL WHERE session_token = ''"
    execute "UPDATE connectors_mcp_servers SET oauth_client_secret = NULL WHERE oauth_client_secret = ''"
  end

  def down
    # intentionally irreversible — empty strings should not be stored in encrypted columns
  end
end
