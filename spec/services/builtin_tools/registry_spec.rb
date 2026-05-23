# frozen_string_literal: true

require "rails_helper"

RSpec.describe BuiltinTools::Registry do
  around do |example|
    original = described_class.definitions.dup
    described_class.definitions.clear
    example.run
  ensure
    described_class.definitions.clear
    described_class.definitions.merge!(original)
  end

  it "registers, looks up, and builds runtime tools" do
    described_class.register(
      "demo.tool",
      name: "Demo",
      description: "Demo tool",
      runtime_name: "demo_runtime",
      icon: "fa-solid fa-bolt",
      tool_call_presentation: {
        running_messages: ["Working…"],
        complete_messages: ["Done."],
      },
    ) { |value:| "built #{value}" }

    expect(described_class.definition_for("demo.tool").name).to eq("Demo")
    expect(described_class.definition_for_runtime_name("demo_runtime")&.icon).to eq("fa-solid fa-bolt")
    expect(described_class.definition_for("demo.tool").presentation.running_messages).to eq(["Working…"])
    expect(described_class.build("demo.tool", value: "ok")).to eq("built ok")
  end

  it "returns visible definitions sorted by name" do
    described_class.register("z.tool", name: "Zulu", description: "Z", visible_in_headquarter: true) { nil }
    described_class.register("a.tool", name: "Alpha", description: "A", visible_in_headquarter: true) { nil }
    described_class.register("hidden.tool", name: "Hidden", description: "H", visible_in_headquarter: false) { nil }

    expect(described_class.visible_definitions.map(&:name)).to eq(["Alpha", "Zulu"])
  end

  it "returns user-assignable definitions sorted by name" do
    described_class.register("z.tool", name: "Zulu", description: "Z", user_assignable: true) { nil }
    described_class.register(
      "a.tool",
      name: "Alpha",
      description: "A",
      user_assignable: true,
      configuration_hint: "Configured elsewhere.",
    ) { nil }
    described_class.register("hidden.tool", name: "Hidden", description: "H") { nil }

    expect(described_class.user_assignable_definitions.map(&:name)).to eq(["Alpha", "Zulu"])
    expect(described_class.user_assignable_keys).to eq(["a.tool", "z.tool"])
    expect(described_class.definition_for("a.tool").configuration_hint).to eq("Configured elsewhere.")
  end

  describe "compaction_policy" do
    it "defaults to nil when not provided" do
      described_class.register("plain.tool", name: "Plain", description: "") { nil }
      expect(described_class.definition_for("plain.tool").compaction_policy).to be_nil
    end

    it "accepts valid MessageCompactor policies" do
      described_class.register(
        "drop.tool", name: "Drop", description: "", compaction_policy: :drop_all,
      ) { nil }

      expect(described_class.definition_for("drop.tool").compaction_policy).to eq(:drop_all)
    end

    it "rejects unknown policies" do
      expect do
        described_class.register(
          "bad.tool", name: "Bad", description: "", compaction_policy: :bogus,
        ) { nil }
      end.to raise_error(ArgumentError, /Unknown compaction policy/)
    end
  end
end
