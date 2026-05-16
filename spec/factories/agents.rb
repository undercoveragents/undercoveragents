# frozen_string_literal: true

# == Schema Information
#
# Table name: agents
# Database name: primary
#
#  id            :bigint           not null, primary key
#  agent_type    :string
#  builtin       :boolean          default(FALSE), not null
#  configuration :jsonb            not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operation_id  :bigint           not null
#
# Indexes
#
#  index_agents_on_agent_type                  (agent_type)
#  index_agents_on_operation_and_name          (operation_id,name) UNIQUE
#  index_agents_on_operation_id                (operation_id)
#  index_agents_on_slug                        (slug) UNIQUE
#  index_agents_on_type_and_operation_builtin  (agent_type,operation_id) UNIQUE WHERE (builtin = true)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
agent_factory_default_llm_connector = Object.new.freeze

FactoryBot.define do
  factory :agent do
    transient do
      llm_connector { agent_factory_default_llm_connector }
    end

    operation { OperationFactoryHelper.default_operation }
    name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    description { Faker::Lorem.sentence }
    instructions { Faker::Lorem.paragraph(sentence_count: 3) }
    model_id { "gpt-4.1" }
    temperature { 0.7 }
    enabled { true }

    after(:build) do |agent, evaluator|
      connector = if evaluator.llm_connector.equal?(agent_factory_default_llm_connector)
                    create(:connector, :llm_provider, :enabled, tenant: agent.operation.tenant)
                  else
                    evaluator.llm_connector
                  end

      agent.llm_connector_id = connector.id if connector
    end

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_sql_tool do
      after(:create) do |agent|
        connector = create(:connector, :sql_database, :enabled)
        sql_query = create(:tools_sql_query, connector:)
        tool = create(:tool, :enabled, toolable: sql_query)
        agent.tool_ids = agent.tool_ids + [tool.id]
        agent.save!
      end
    end

    trait :with_title_generator do
      after(:create) do |agent|
        agent.set_capability_config("chat_title_generator", {
                                      "max_length" => 30,
                                      "max_turns" => 3,
                                      "llm_config_source" => "inherit",
                                      "temperature" => 0.7,
                                    }, enabled: true,)
        agent.save!
      end
    end

    trait :with_subagent do
      after(:create) do |agent|
        subagent = create(:agent, :enabled)
        agent.subagent_ids = agent.subagent_ids + [subagent.id]
        agent.save!
      end
    end
  end
end
