# frozen_string_literal: true

# == Schema Information
#
# Table name: test_suites
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  description                 :text
#  evaluation_temperature      :float            default(0.7), not null
#  name                        :string           not null
#  slug                        :string
#  source_metadata             :jsonb            not null
#  source_type                 :string           default("manual"), not null
#  status                      :string           default("active"), not null
#  suite_type                  :string           default("agent"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  agent_id                    :bigint
#  evaluation_llm_connector_id :bigint
#  evaluation_model_id         :string
#  mission_id                  :bigint
#
# Indexes
#
#  index_test_suites_on_agent_id                     (agent_id)
#  index_test_suites_on_builtin_key                  (((source_metadata ->> 'builtin_key'::text))) WHERE ((source_type)::text = 'builtin'::text)
#  index_test_suites_on_evaluation_llm_connector_id  (evaluation_llm_connector_id)
#  index_test_suites_on_mission_id                   (mission_id)
#  index_test_suites_on_name                         (name)
#  index_test_suites_on_slug                         (slug) UNIQUE
#  index_test_suites_on_source_type                  (source_type)
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (evaluation_llm_connector_id => connectors.id)
#  fk_rails_...  (mission_id => missions.id)
#
FactoryBot.define do
  factory :test_suite do
    agent
    name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    description { Faker::Lorem.sentence }
    status { "active" }

    trait :active do
      status { "active" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :mission_suite do
      suite_type { "mission" }
      agent { nil }
      mission
    end

    trait :with_test_cases do
      after(:create) do |test_suite|
        if test_suite.mission?
          create_list(:test_case, 3, :mission_case, test_suite:)
        else
          create_list(:test_case, 3, test_suite:)
        end
      end
    end

    trait :with_evaluation_llm do
      evaluation_llm_connector factory: [:connector, :llm_provider]
      evaluation_model_id { "gpt-4.1-mini" }
      evaluation_temperature { 0.3 }
    end
  end
end
