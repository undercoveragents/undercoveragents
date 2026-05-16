class AddNameToPipelineVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :pipeline_versions, :name, :string
  end
end
