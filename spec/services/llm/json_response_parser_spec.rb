# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::JsonResponseParser do
  describe ".parse" do
    it "returns native hash and array content directly" do
      expect(described_class.parse({ "ok" => true }).data).to eq({ "ok" => true })
      expect(described_class.parse([1, 2]).data).to eq([1, 2])
    end

    it "parses raw, fenced, and prose-wrapped JSON" do
      expect(described_class.parse('{"answer":"yes"}').data).to eq({ "answer" => "yes" })
      expect(described_class.parse("```json\n[1,2]\n```").data).to eq([1, 2])
      expect(described_class.parse('Result: {"text":"brace } inside"} done').data).to eq(
        { "text" => "brace } inside" },
      )
      expect(described_class.parse('Result: {"text":"escaped \\" quote"} done').data).to eq(
        { "text" => 'escaped " quote' },
      )
    end

    it "reports empty and invalid content without raising" do
      blank_result = described_class.parse("   ")
      invalid_result = described_class.parse("No JSON here")
      unbalanced_result = described_class.parse('Before {"missing": true')

      expect(blank_result).not_to be_success
      expect(blank_result.error).to eq("No JSON content found")
      expect(invalid_result.error).to eq("No valid JSON object or array found")
      expect(unbalanced_result.error).to eq("No valid JSON object or array found")
    end
  end
end
