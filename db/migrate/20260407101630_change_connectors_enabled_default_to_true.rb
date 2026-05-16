class ChangeConnectorsEnabledDefaultToTrue < ActiveRecord::Migration[8.1]
  def change
    change_column_default :connectors, :enabled, from: false, to: true
  end
end
