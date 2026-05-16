# frozen_string_literal: true

# == Schema Information
#
# Table name: test_cases
# Database name: primary
#
#  id                         :bigint           not null, primary key
#  category                   :string
#  complexity                 :string
#  disallow_child_chats       :boolean          default(FALSE), not null
#  expected_answer            :text
#  expected_child_builtin_key :string
#  expected_status            :string
#  expected_tool_names        :jsonb            not null
#  expected_variables         :jsonb            not null
#  fixture_key                :string
#  forbidden_keywords         :jsonb            not null
#  input_variables            :jsonb            not null
#  match_type                 :string           default("semantic"), not null
#  name                       :string
#  position                   :integer          default(0), not null
#  prompt                     :text
#  required_keywords          :jsonb            not null
#  scenario_key               :string
#  source_metadata            :jsonb            not null
#  source_type                :string           default("manual"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  test_suite_id              :bigint           not null
#
# Indexes
#
#  index_test_cases_on_scenario_key                (scenario_key)
#  index_test_cases_on_source_type                 (source_type)
#  index_test_cases_on_suite_and_scenario_key      (test_suite_id,scenario_key) UNIQUE WHERE (scenario_key IS NOT NULL)
#  index_test_cases_on_test_suite_id               (test_suite_id)
#  index_test_cases_on_test_suite_id_and_position  (test_suite_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (test_suite_id => test_suites.id)
#
FactoryBot.define do
  factory :test_case do
    test_suite
    prompt { Faker::Lorem.question }
    expected_answer { Faker::Lorem.paragraph }
    match_type { "semantic" }
    sequence(:position)

    trait :exact do
      match_type { "exact" }
    end

    trait :semantic do
      match_type { "semantic" }
    end

    trait :mission_case do
      test_suite factory: [:test_suite, :mission_suite]
      prompt { nil }
      expected_answer { nil }
      name { Faker::Lorem.words(number: 3).join(" ").titleize }
      expected_status { "completed" }
      match_type { "exact" }
      input_variables { { "query" => "test input" } }
      expected_variables { { "result" => "expected output" } }
    end
  end
end
