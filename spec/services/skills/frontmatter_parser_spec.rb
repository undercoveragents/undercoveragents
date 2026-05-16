# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::FrontmatterParser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    it "parses valid frontmatter and normalizes metadata" do
      result = parser.parse(
        <<~MARKDOWN,
          ---
          name: triage-guide
          description: Use this skill when a support request needs triage.
          metadata:
            owner: ops
          ---

          # Triage
        MARKDOWN
        directory_name: "triage-guide",
      )

      expect(result).to be_success
      expect(result.attributes[:name]).to eq("triage-guide")
      expect(result.attributes[:metadata]).to eq("owner" => "ops")
    end

    it "fails when frontmatter is missing" do
      result = parser.parse("# Missing frontmatter\n")

      expect(result).not_to be_success
      expect(result.error_message).to eq("SKILL.md must start with YAML frontmatter.")
    end

    it "fails when the description is blank" do
      result = parser.parse(
        <<~MARKDOWN,
          ---
          name: triage-guide
          description:
          ---

          # Triage
        MARKDOWN
      )

      expect(result).not_to be_success
      expect(result.error_message).to eq("Every skill must include a non-empty description.")
    end

    it "fails when no name can be resolved" do
      result = parser.parse(
        <<~MARKDOWN,
          ---
          description: Use this skill when triage guidance is needed.
          ---

          # Triage
        MARKDOWN
      )

      expect(result).not_to be_success
      expect(result.error_message).to eq("Every skill must include a name.")
    end

    it "infers the name from the directory and records a warning" do
      result = parser.parse(
        <<~MARKDOWN,
          ---
          description: Use this skill when triage guidance is needed.
          ---

          # Triage
        MARKDOWN
        directory_name: "triage-guide",
      )

      expect(result).to be_success
      expect(result.attributes[:name]).to eq("triage-guide")
      expect(result.warnings).to include("The skill name was inferred from the directory name.")
    end

    it "fails when YAML cannot be parsed even after retrying quoted values" do
      result = parser.parse(
        <<~MARKDOWN,
          ---
          name: [oops
          description: broken
          ---

          # Broken
        MARKDOWN
      )

      expect(result).not_to be_success
      expect(result.error_message).to eq("The SKILL.md frontmatter could not be parsed.")
    end

    it "leaves already quoted colon values untouched when retrying YAML quoting" do
      quoted = <<~YAML
        description: "already: quoted"
      YAML

      expect(parser.send(:quote_common_colon_values, quoted)).to eq(quoted)
    end
  end
end
