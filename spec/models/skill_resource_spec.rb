# frozen_string_literal: true

# == Schema Information
#
# Table name: skill_resources
# Database name: primary
#
#  id            :bigint           not null, primary key
#  relative_path :string           not null
#  resource_kind :string           default("other"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  skill_id      :bigint           not null
#
# Indexes
#
#  index_skill_resources_on_skill_id                    (skill_id)
#  index_skill_resources_on_skill_id_and_relative_path  (skill_id,relative_path) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (skill_id => skills.id)
#
require "rails_helper"

RSpec.describe SkillResource do
  describe "#filename" do
    it "returns the basename of the relative path" do
      resource = build(:skill_resource, relative_path: "references/checklist.md")

      expect(resource.filename).to eq("checklist.md")
    end
  end

  describe "callbacks and validations" do
    it "normalizes the relative path and infers the resource kind" do
      resource = build(:skill_resource, relative_path: "//references//guide.md")

      resource.validate

      expect(resource.relative_path).to eq("references/guide.md")
      expect(resource.resource_kind).to eq("references")
    end

    it "rejects unsafe relative paths" do
      resource = build(:skill_resource, relative_path: "../secret.txt")

      expect(resource).not_to be_valid
      expect(resource.errors[:relative_path]).to include("must stay inside the skill directory")
    end

    it "returns early from the safety check when the path is blank" do
      resource = build(:skill_resource, relative_path: "")

      resource.validate

      expect(resource.errors[:relative_path]).to include("can't be blank")
      expect(resource.errors[:relative_path]).not_to include("must stay inside the skill directory")
    end

    it "requires an attached file" do
      resource = build(:skill_resource)
      resource.file.detach

      expect(resource).not_to be_valid
      expect(resource.errors[:file]).to include("must be attached")
    end
  end
end
