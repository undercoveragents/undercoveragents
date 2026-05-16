class CreateCustomCodeRagSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :rag_steps_custom_code_sources do |t|
      t.timestamps
    end

    create_table :rag_steps_custom_code_chunkers do |t|
      t.timestamps
    end

    create_table :rag_steps_custom_code_embedders do |t|
      t.timestamps
    end

    create_table :rag_steps_custom_code_storages do |t|
      t.timestamps
    end
  end
end
