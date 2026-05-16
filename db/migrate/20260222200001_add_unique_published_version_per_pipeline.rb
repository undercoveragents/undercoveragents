# frozen_string_literal: true

class AddUniquePublishedVersionPerPipeline < ActiveRecord::Migration[8.1]
  def change
    add_index :pipeline_versions,
              :pipeline_id,
              where: "status = 'published'",
              unique: true,
              name: "index_pipeline_versions_unique_published_per_pipeline"
  end
end
