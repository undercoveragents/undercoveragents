# frozen_string_literal: true

# == Schema Information
#
# Table name: tools
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  description   :text
#  enabled       :boolean          default(TRUE), not null
#  name          :string           not null
#  slug          :string           not null
#  tool_type     :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operation_id  :bigint           not null
#
# Indexes
#
#  index_tools_on_enabled                (enabled)
#  index_tools_on_operation_id           (operation_id)
#  index_tools_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_tools_on_slug                   (slug) UNIQUE
#  index_tools_on_tool_type              (tool_type)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
FactoryBot.define do
  factory :tool do
    operation { OperationFactoryHelper.default_operation }
    name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    description { Faker::Lorem.sentence }
    enabled { false }

    trait :sql_query do
      after(:build) do |tool|
        sq = Tools::SqlQuery.new(
          discovered_schema: {},
          selected_objects: [],
          llm_config_source: "inherit",
        )
        tool.toolable = sq
      end
    end

    trait :mcp_server do
      after(:build) do |tool|
        tool.toolable = Tools::McpServer.new(
          discovered_tools: [],
          selected_tools: [],
        )
      end
    end

    trait :rag_query do
      after(:build) do |tool|
        tool.toolable = Tools::RagQuery.new(
          chunks_table: "chunks",
          documents_table: "documents",
          chunk_content_field: "content",
          embedding_field: "embedding",
          document_reference_field: "document_id",
          distance_method: "cosine",
          results_limit: 10,
        )
      end
    end

    trait :rag_flow do
      after(:build) do |tool|
        tool.toolable = Tools::RagFlow.new(
          distance_method: "cosine",
          results_limit: 10,
          max_distance: 0.8,
        )
      end
    end

    trait :mission_tool do
      after(:build) do |tool|
        mission = create(:mission)
        tool.toolable = Tools::MissionTool.new(mission_id: mission.id)
      end
    end

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
