class RemoveUniquePublishedConstraintFromPipelineVersions < ActiveRecord::Migration[8.1]
  def change
    remove_index :pipeline_versions, name: :index_pipeline_versions_one_published_per_pipeline
  end
end
