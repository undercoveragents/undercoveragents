# frozen_string_literal: true

# rubocop:disable Style/FormatStringToken

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
require "rails_helper"

RSpec.describe TestCase do
  subject(:test_case) { build(:test_case) }

  describe "associations" do
    it { is_expected.to belong_to(:test_suite).inverse_of(:test_cases) }
    it { is_expected.to have_many(:test_case_results).dependent(:destroy).inverse_of(:test_case) }
  end

  describe "validations" do
    context "when agent test suite" do
      subject(:test_case) { build(:test_case) }

      it { is_expected.to validate_presence_of(:prompt) }
      it { is_expected.to validate_length_of(:prompt).is_at_most(5000) }
      it { is_expected.to validate_presence_of(:expected_answer) }
      it { is_expected.to validate_length_of(:expected_answer).is_at_most(10_000) }
    end

    context "when mission test suite" do
      subject(:test_case) { build(:test_case, :mission_case) }

      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_length_of(:name).is_at_most(200) }

      it "validates expected_status inclusion" do
        test_case.expected_status = "invalid"
        expect(test_case).not_to be_valid
      end
    end

    it { is_expected.to validate_inclusion_of(:source_type).in_array(["manual", "builtin"]) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }
  end

  describe "enums" do
    it {
      expect(test_case).to define_enum_for(:match_type)
        .with_values(exact: "exact", semantic: "semantic", partial: "partial")
        .backed_by_column_of_type(:string)
    }
  end

  describe "scopes" do
    describe ".ordered" do
      it "returns test cases ordered by position" do
        suite = create(:test_suite)
        case_two = create(:test_case, test_suite: suite, position: 2)
        case_one = create(:test_case, test_suite: suite, position: 1)

        expect(described_class.ordered).to eq([case_one, case_two])
      end
    end
  end

  describe "#display_label" do
    it "returns name when present" do
      tc = build(:test_case, name: "My Test", prompt: "Some prompt")
      expect(tc.display_label).to eq("My Test")
    end

    it "falls back to truncated prompt when name is blank" do
      tc = build(:test_case, name: nil, prompt: "A very long prompt")
      expect(tc.display_label).to eq("A very long prompt")
    end

    it "truncates long prompts to 80 characters" do
      tc = build(:test_case, name: nil, prompt: "x" * 100)
      expect(tc.display_label.length).to be <= 80
    end

    it "returns nil when both name and prompt are nil" do
      tc = build(:test_case, name: nil, prompt: nil)
      expect(tc.display_label).to be_nil
    end
  end

  describe "behavior expectations" do
    it "reports builtin source type" do
      expect(build(:test_case, source_type: "builtin")).to be_builtin
    end

    it "is true when a behavior field is configured" do
      tc = build(:test_case, expected_tool_names: ["list_resources"])

      expect(tc).to be_behavior_expectations
    end

    it "renders template placeholders from the fixture context" do
      tc = build(
        :test_case,
        prompt: "Create %{new_agent_name}",
        expected_answer: "%{new_agent_name} created",
        required_keywords: ["%{new_agent_name}"],
      )

      context = { new_agent_name: "AAB New Agent" }

      expect(tc.rendered_prompt(context)).to eq("Create AAB New Agent")
      expect(tc.rendered_expected_answer(context)).to eq("AAB New Agent created")
      expect(tc.rendered_required_keywords(context)).to eq(["AAB New Agent"])
    end

    it "leaves templates unchanged when a placeholder is missing" do
      tc = build(:test_case, prompt: "Create %{missing_name}")

      expect(tc.rendered_prompt({ other_name: "Ignored" })).to eq("Create %{missing_name}")
    end

    it "adds validation errors for invalid JSON column shapes" do
      tc = build(:test_case)
      tc.source_metadata = []
      tc.expected_tool_names = {}
      tc.required_keywords = {}
      tc.forbidden_keywords = {}

      tc.send(:json_columns_must_have_expected_shape)

      expect(tc.errors.attribute_names).to include(
        :source_metadata,
        :expected_tool_names,
        :required_keywords,
        :forbidden_keywords,
      )
    end

    it "normalizes invalid source metadata before validation" do
      tc = build(:test_case)
      tc.source_metadata = []

      tc.valid?

      expect(tc.source_metadata).to eq({})
    end
  end
end
# rubocop:enable Style/FormatStringToken
