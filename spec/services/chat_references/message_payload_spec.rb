# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatReferences::MessagePayload do
  let(:references) do
    [
      {
        "kind" => "missions",
        "id" => 23,
        "type" => "Mission",
        "label" => "Test Mission",
        "slug" => "test-mission",
        "mention" => "#test-mission",
      },
    ]
  end

  it "packs references into a hidden message marker" do
    packed = described_class.pack(content: "Update #test-mission", references:)
    payload = described_class.parse(packed)

    expect(payload.display_content).to eq("Update #test-mission")
    expect(payload.references).to eq(references)
    expect(payload.prompt_content).to eq(
      "Update mission id: 23\nReferenced records:\n" \
      "- #test-mission => Mission: Test Mission | id: 23 | slug: test-mission",
    )
    expect(payload).to be_references
  end

  it "keeps multiple inline references mapped to their exact prompt-safe ids" do
    second_reference = references.first.merge(
      "id" => 42,
      "label" => "Second Mission",
      "slug" => "second-mission",
      "mention" => "#test-mission-2",
    )
    payload = described_class.new(
      content: "Compare #test-mission and #test-mission-2",
      references: references + [second_reference],
    )

    expect(payload.prompt_content).to eq(
      "Compare mission id: 23 and mission id: 42\n" \
      "Referenced records:\n" \
      "- #test-mission => Mission: Test Mission | id: 23 | slug: test-mission\n" \
      "- #test-mission-2 => Mission: Second Mission | id: 42 | slug: second-mission",
    )
  end

  it "appends context-only reference ids to the prompt" do
    payload = described_class.new(
      content: "Is it valid?",
      references: [references.first.except("mention", "display_mention", "display_tag", "prompt_text")],
    )

    expect(payload.prompt_content).to eq(
      "Is it valid?\nReferenced records:\n" \
      "- Test Mission => Mission: Test Mission | id: 23 | slug: test-mission",
    )
  end

  it "appends referenced ids when the inline token is no longer in the content" do
    payload = described_class.new(content: "Is it valid?", references:)

    expect(payload.prompt_content).to eq(
      "Is it valid?\nReferenced records:\n" \
      "- Test Mission => Mission: Test Mission | id: 23 | slug: test-mission",
    )
  end

  it "ignores references without prompt text when building the prompt" do
    payload = described_class.new(content: "Hello", references: [{ "label" => "Launch Plan" }])

    expect(payload.prompt_content).to eq("Hello")
  end

  it "falls back to a bare prompt id when a reference has no display label" do
    payload = described_class.new(content: "Hello", references: [{ "prompt_text" => "mission id: 23" }])

    expect(payload.prompt_content).to eq("Hello\nReferenced records:\n- mission id: 23")
  end

  it "builds a label-based reference summary when only prompt-safe label metadata is available" do
    payload = described_class.new(
      content: "Hello",
      references: [{ "label" => "Stage selector", "prompt_text" => "stage selector" }],
    )

    expect(payload.prompt_content).to eq("Hello\nReferenced records:\n- Stage selector => Stage selector")
  end

  it "returns plain content when there are no references" do
    payload = described_class.parse(described_class.pack(content: "Hello", references: []))

    expect(payload.display_content).to eq("Hello")
    expect(payload.prompt_content).to eq("Hello")
    expect(payload.references).to eq([])
    expect(payload).not_to be_references
  end

  it "ignores corrupt reference markers" do
    payload = described_class.parse("Hello\n\n<!-- chat_references:not-json -->")

    expect(payload.display_content).to eq("Hello\n\n<!-- chat_references:not-json -->")
    expect(payload.references).to eq([])
  end

  it "strips markers with unreadable encoded references" do
    encoded_json = Base64.strict_encode64("not json")

    expect(described_class.parse("Hello\n\n<!-- chat_references:abc -->").references).to eq([])
    expect(described_class.parse("Hello\n\n<!-- chat_references:#{encoded_json} -->").display_content).to eq("Hello")
  end
end
