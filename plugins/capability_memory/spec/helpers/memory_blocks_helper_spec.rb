# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryBlocksHelper do
  describe "#memory_block_usage_percentage" do
    it "returns 0 when the block has no character limit" do
      block = build(:memory_block, char_limit: 0, default_value: "hello")

      expect(helper.memory_block_usage_percentage(block)).to eq(0)
    end

    it "caps usage at 100 percent" do
      block = build(:memory_block, char_limit: 10, default_value: "x" * 15)

      expect(helper.memory_block_usage_percentage(block)).to eq(100)
    end
  end

  describe "#memory_block_usage_color_class" do
    it "returns the success class below 70 percent" do
      block = build(:memory_block, char_limit: 100, default_value: "x" * 69)

      expect(helper.memory_block_usage_color_class(block)).to eq("text-success-500")
    end

    it "returns the warning class from 70 to 89 percent" do
      block = build(:memory_block, char_limit: 100, default_value: "x" * 70)

      expect(helper.memory_block_usage_color_class(block)).to eq("text-warning-500")
    end

    it "returns the danger class from 90 percent onward" do
      block = build(:memory_block, char_limit: 100, default_value: "x" * 90)

      expect(helper.memory_block_usage_color_class(block)).to eq("text-danger-500")
    end
  end

  describe "#memory_block_usage_bar_class" do
    it "returns the success bar class below 70 percent" do
      block = build(:memory_block, char_limit: 100, default_value: "x" * 69)

      expect(helper.memory_block_usage_bar_class(block)).to eq("bg-success-500")
    end

    it "returns the warning bar class from 70 to 89 percent" do
      block = build(:memory_block, char_limit: 100, default_value: "x" * 70)

      expect(helper.memory_block_usage_bar_class(block)).to eq("bg-warning-500")
    end

    it "returns the danger bar class from 90 percent onward" do
      block = build(:memory_block, char_limit: 100, default_value: "x" * 90)

      expect(helper.memory_block_usage_bar_class(block)).to eq("bg-danger-500")
    end
  end
end
