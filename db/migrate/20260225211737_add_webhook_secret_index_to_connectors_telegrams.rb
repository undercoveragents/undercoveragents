class AddWebhookSecretIndexToConnectorsTelegrams < ActiveRecord::Migration[8.1]
  def change
    add_index :connectors_telegrams, :webhook_secret, unique: true, where: "webhook_secret IS NOT NULL"
  end
end
