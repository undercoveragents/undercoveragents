# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::SpecificationValidator do
  describe "#warnings" do
    it "reports missing names" do
      warnings = described_class.new(name: "", description: "Short").warnings

      expect(warnings).to include("The skill is missing a name.")
    end

    it "reports invalid formats, long fields, and directory mismatches" do
      warnings = described_class.new(
        name: "Bad Skill Name",
        description: "x" * 1025,
        compatibility: "y" * 501,
        directory_name: "different-folder",
      ).warnings

      expect(warnings).to include("The skill name should use lowercase letters, numbers, and single hyphens only.")
      expect(warnings).to include("The description exceeds the Agent Skills recommendation of 1024 characters.")
      expect(warnings).to include("The compatibility note exceeds the Agent Skills recommendation of 500 characters.")
      expect(warnings).to include("The imported directory name does not match the skill name frontmatter.")
    end

    it "warns when the skill name exceeds 64 characters" do
      warnings = described_class.new(name: "a" * 65, description: "Short").warnings

      expect(warnings).to include("The skill name exceeds the Agent Skills recommendation of 64 characters.")
    end
  end
end
