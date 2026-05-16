# frozen_string_literal: true

# == Schema Information
#
# Table name: skills
# Database name: primary
#
#  id               :bigint           not null, primary key
#  allowed_tools    :string
#  compatibility    :string
#  description      :text             not null
#  instructions     :text
#  license          :string
#  metadata         :jsonb            not null
#  name             :string           not null
#  source_metadata  :jsonb            not null
#  source_type      :string           default("manual"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  skill_catalog_id :bigint           not null
#
# Indexes
#
#  index_skills_on_skill_catalog_id           (skill_catalog_id)
#  index_skills_on_skill_catalog_id_and_name  (skill_catalog_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (skill_catalog_id => skill_catalogs.id)
#
require "rails_helper"

RSpec.describe Skill do
  describe "associations" do
    it { is_expected.to belong_to(:skill_catalog) }
    it { is_expected.to have_many(:skill_resources).dependent(:destroy) }
  end

  describe "validations" do
    subject(:skill) { build(:skill) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:skill_catalog_id) }
  end

  describe "#skill_markdown" do
    it "renders canonical skill markdown with optional frontmatter fields" do
      skill = build(
        :skill,
        license: "Apache-2.0",
        compatibility: "Requires git",
        allowed_tools: "Read",
        metadata: { "author" => "ops" },
      )

      expect(skill.skill_markdown).to include(
        "name: #{skill.name}",
        "license: Apache-2.0",
        "compatibility: Requires git",
        "allowed-tools: Read",
        "author: ops",
        skill.instructions.strip,
      )
    end
  end

  describe "source helpers" do
    it "reports whether a skill is manual, imported, or builtin" do
      expect(build(:skill)).to be_manual
      expect(build(:skill, :imported)).to be_imported
      expect(build(:skill, :builtin)).to be_builtin
    end

    it "builds a stable skill identifier" do
      skill = create(:skill)

      expect(skill.skill_identifier).to eq("#{skill.skill_catalog.slug}/#{skill.id}")
    end

    it "builds a stable builtin skill identifier from builtin keys" do
      skill_catalog = create(
        :skill_catalog,
        :builtin,
        source_metadata: { "builtin_key" => "undercover-agents-missions" },
      )
      skill = create(
        :skill,
        :builtin,
        skill_catalog:,
        source_metadata: { "builtin_key" => "mission-designer-workbench" },
      )

      expect(skill.skill_identifier).to eq("undercover-agents-missions/mission-designer-workbench")
    end
  end

  describe "normalization and JSON helpers" do
    it "normalizes optional text fields and JSON columns" do
      skill = build(
        :skill,
        license: "  ",
        compatibility: "  ",
        allowed_tools: "  ",
        metadata: [],
        source_metadata: [],
      )

      skill.send(:normalize_json_columns)
      skill.send(:normalize_strings)

      expect(skill.license).to be_nil
      expect(skill.compatibility).to be_nil
      expect(skill.allowed_tools).to be_nil
      expect(skill.metadata).to eq({})
      expect(skill.source_metadata).to eq({})
    end

    it "adds errors when JSON columns are not hashes" do
      skill = build(:skill)
      skill.metadata = "bad"
      skill.source_metadata = "bad"

      skill.send(:json_columns_must_be_hashes)

      expect(skill.errors[:metadata]).to include("must be a JSON object")
      expect(skill.errors[:source_metadata]).to include("must be a JSON object")
    end
  end

  describe "#spec_warnings" do
    it "reports non-standard skill names" do
      skill = build(:skill, name: "Bad Skill")
      expected_warning = "The skill name should use lowercase letters, numbers, and single hyphens only."

      expect(skill.spec_warnings).to include(expected_warning)
    end
  end
end
