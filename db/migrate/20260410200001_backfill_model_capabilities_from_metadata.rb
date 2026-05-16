# frozen_string_literal: true

class BackfillModelCapabilitiesFromMetadata < ActiveRecord::Migration[8.1]
  def up
    # Add "temperature" capability for models that support it via metadata
    execute <<~SQL
      UPDATE models
      SET capabilities = capabilities || '["temperature"]'
      WHERE (metadata->>'temperature')::boolean = true
        AND NOT (capabilities @> '["temperature"]')
    SQL

    # Add "open_weights" capability for models with open weights via metadata
    execute <<~SQL
      UPDATE models
      SET capabilities = capabilities || '["open_weights"]'
      WHERE (metadata->>'open_weights')::boolean = true
        AND NOT (capabilities @> '["open_weights"]')
    SQL
  end

  def down
    execute <<~SQL
      UPDATE models
      SET capabilities = (
        SELECT jsonb_agg(cap)
        FROM jsonb_array_elements_text(capabilities) AS cap
        WHERE cap NOT IN ('temperature', 'open_weights')
      )
    SQL
  end
end
