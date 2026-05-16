# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolDesigner::FieldMetadata do
  def build_field_metadata_tool
    stub_const("FieldMetadataTool", Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations

      attribute :array_default, default: -> { ["one"] }
      attribute :count, :integer
      attribute :empty_enum, :string
      attribute :hash_default, default: -> { { "key" => "value" } }
      attribute :limited_text, :string
      attribute :loose_number, :integer

      validates :count, numericality: true
      validates :empty_enum, inclusion: { in: [] }
      validates :limited_text, length: { minimum: 1 }
      validates :loose_number, numericality: { greater_than: 0, less_than_or_equal_to: 9 }

      def self.tool_designer_field_hints = {}
    end,)
    FieldMetadataTool
  end

  def metadata_for(klass)
    described_class.new(klass, klass.new)
  end

  it "renders fields for classes without validators" do
    klass = Class.new do
      def self.tool_designer_field_hints = {}
    end

    expect(described_class.new(klass, Object.new).line("manual_field")).to eq(
      "- `manual_field` (value, optional)",
    )
  end

  it "handles optional constraints and default JSON values", :aggregate_failures do
    metadata = metadata_for(build_field_metadata_tool)

    expect(metadata.line("empty_enum")).to eq("- `empty_enum` (string, optional)")
    expect(metadata.line("count")).to eq("- `count` (integer, optional)")
    expect(metadata.line("limited_text")).to eq("- `limited_text` (string, optional)")
    expect(metadata.line("loose_number")).to include("Numeric constraint: > 0, <= 9.")
    expect(metadata.line("array_default")).to include("Default: `[\"one\"]`.")
    expect(metadata.line("hash_default")).to include("Default: `{")
  end

  it "ignores validator value sources that cannot be listed" do
    metadata = described_class.new(build_field_metadata_tool, build_field_metadata_tool.new)

    expect(metadata.send(:validator_values, Object.new)).to be_nil
    expect(metadata.send(:validator_values, ->(_) { raise "boom" })).to be_nil
  end
end
