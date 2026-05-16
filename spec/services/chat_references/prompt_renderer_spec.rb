# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatReferences::PromptRenderer do
  it "replaces selected mention tokens with prompt-safe resource identifiers" do
    rendered = described_class.new(
      content: "Update #mission and attach #tool.",
      references: [
        { "mention" => "#mission", "type" => "Mission", "id" => 5 },
        { "mention" => "#tool", "type" => "Tool", "id" => 9 },
      ],
    ).render

    expect(rendered).to eq("Update mission id: 5 and attach tool id: 9.")
  end

  it "replaces longer mentions before their prefixes" do
    rendered = described_class.new(
      content: "Compare #mission-abc with #mission.",
      references: [
        { "mention" => "#mission", "type" => "Mission", "id" => 5 },
        { "mention" => "#mission-abc", "type" => "Mission", "id" => 8 },
      ],
    ).render

    expect(rendered).to eq("Compare mission id: 8 with mission id: 5.")
  end

  it "leaves mention tokens unchanged when a reference has no prompt-safe identifier" do
    rendered = described_class.new(
      content: "Update #mission.",
      references: [{ "mention" => "#mission", "label" => "Launch Plan" }],
    ).render

    expect(rendered).to eq("Update #mission.")
  end
end
