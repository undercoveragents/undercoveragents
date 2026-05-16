# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryBlock do
  subject(:memory_block) { build(:memory_block) }

  describe "associations" do
    it { is_expected.to have_many(:agent_memory_blocks).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:label) }
    it { is_expected.to validate_numericality_of(:char_limit).only_integer.is_greater_than(0) }

    it "accepts true and false for read_only" do
      [true, false].each do |val|
        memory_block.read_only = val
        expect(memory_block).to be_valid
      end
    end

    describe "label format" do
      it "allows lowercase letters and underscores" do
        memory_block.label = "persona_notes"
        expect(memory_block).to be_valid
      end

      it "rejects uppercase letters" do
        memory_block.label = "Persona"
        expect(memory_block).not_to be_valid
        expect(memory_block.errors[:label]).to be_present
      end

      it "rejects spaces" do
        memory_block.label = "my block"
        expect(memory_block).not_to be_valid
      end

      it "rejects hyphens" do
        memory_block.label = "my-block"
        expect(memory_block).not_to be_valid
      end
    end

    describe "default_value length" do
      it "allows default_value within char_limit" do
        memory_block.char_limit = 100
        memory_block.default_value = "a" * 100
        expect(memory_block).to be_valid
      end

      it "rejects default_value exceeding char_limit" do
        memory_block.char_limit = 10
        memory_block.default_value = "a" * 11
        expect(memory_block).not_to be_valid
        expect(memory_block.errors[:default_value]).to be_present
      end
    end
  end

  describe "scopes" do
    describe ".ordered" do
      it "returns blocks ordered by label" do
        block_b = create(:memory_block, label: "beta")
        block_a = create(:memory_block, label: "alpha")
        block_c = create(:memory_block, label: "gamma")

        expect(described_class.ordered).to eq([block_a, block_b, block_c])
      end
    end
  end

  describe "#render_xml" do
    it "renders tag structure using given value" do
      memory_block = build(:memory_block, label: "persona", description: "Agent persona",
                                          default_value: "I am helpful.", char_limit: 5000,)
      xml = memory_block.render_xml(value: "I am helpful.")

      expect(xml).to include("<persona>")
      expect(xml).to include("</persona>")
      expect(xml).to include("<description>Agent persona</description>")
    end

    it "renders metadata and value" do
      memory_block = build(:memory_block, label: "persona", description: "Agent persona",
                                          default_value: "I am helpful.", char_limit: 5000,)
      xml = memory_block.render_xml(value: "I am helpful.")

      expect(xml).to include("chars_current=13")
      expect(xml).to include("chars_limit=5000")
      expect(xml).to include("<value>I am helpful.</value>")
    end

    it "falls back to default_value when no value arg is passed" do
      memory_block = build(:memory_block, label: "persona", default_value: "Default content", char_limit: 5000)
      xml = memory_block.render_xml

      expect(xml).to include("Default content")
    end

    it "escapes HTML entities in value and description" do
      memory_block = build(:memory_block, label: "test", description: "Has <html>",
                                          default_value: "A & B", char_limit: 5000,)
      xml = memory_block.render_xml(value: "A & B")

      expect(xml).to include("Has &lt;html&gt;")
      expect(xml).to include("A &amp; B")
    end
  end

  describe "#chars_remaining" do
    it "returns the available character count based on default_value" do
      memory_block = build(:memory_block, char_limit: 100, default_value: "hello")
      expect(memory_block.chars_remaining).to eq(95)
    end

    it "returns full limit when default_value is empty" do
      memory_block = build(:memory_block, char_limit: 500, default_value: "")
      expect(memory_block.chars_remaining).to eq(500)
    end
  end
end
