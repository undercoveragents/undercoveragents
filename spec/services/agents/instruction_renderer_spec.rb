# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::InstructionRenderer do
  describe ".render" do
    it "returns an empty string for blank templates" do
      expect(described_class.render(nil)).to eq("")
    end

    it "renders agent, user, object, array, and active record values safely" do
      agent = build(:agent, builtin: true, builtin_key: "agent_alpha")
      user = create(:user)
      presenter = Struct.new(:name).new("Ada")
      template = [
        "Agent {{agent.name}} / User {{user.email}}",
        "Object {{presenter.name}} / Tags {{tags}}",
        "Record {{record.email}}",
      ].join(" / ")

      rendered = described_class.render(
        template,
        agent:,
        user:,
        input_values: {
          presenter:,
          tags: ["one", "two"],
          record: user,
        },
      )

      expect(rendered).to include(
        "Agent #{agent.name}",
        "User #{user.email}",
        "Object Ada",
        JSON.pretty_generate(["one", "two"]),
        "Record #{user.email}",
      )
    end

    it "preserves unknown tokens so literal mission placeholders survive" do
      rendered = described_class.render("Hello {{missing.token}}")

      expect(rendered).to eq("Hello {{missing.token}}")
    end

    it "renders missing input schema values as empty strings" do
      agent = build(:agent, input_schema: [{ variable_name: "mission_name", label: "Mission", field_type: "string" }])

      rendered = described_class.render("Current mission: {{mission_name}}", agent:)

      expect(rendered).to eq("Current mission: ")
    end

    it "renders explicit nil input values as empty strings" do
      rendered = described_class.render("Optional: {{optional_value}}", input_values: { optional_value: nil })

      expect(rendered).to eq("Optional: ")
    end

    it "preserves unknown object member tokens" do
      presenter = Struct.new(:name).new("Ada")

      rendered = described_class.render("Unknown: {{presenter.missing}}", input_values: { presenter: })

      expect(rendered).to eq("Unknown: {{presenter.missing}}")
    end

    it "does not treat ellipsis examples as template tokens" do
      rendered = described_class.render("Wrap identifiers in {{...}} and keep {{input}} literal.")

      expect(rendered).to eq("Wrap identifiers in {{...}} and keep {{input}} literal.")
    end
  end
end
