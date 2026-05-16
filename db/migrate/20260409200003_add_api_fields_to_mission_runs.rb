# frozen_string_literal: true

class AddApiFieldsToMissionRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :mission_runs, :callback_url, :string
    add_reference :mission_runs, :api_client, null: true, foreign_key: true
  end
end
