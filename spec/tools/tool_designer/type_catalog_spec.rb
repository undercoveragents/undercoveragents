# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolDesigner::TypeCatalog do
  def register_tool_type(klass, description: "")
    ToolPlugin.register(
      klass.type_key,
      klass.name,
      label: klass.type_label,
      icon: klass.type_icon,
      description:,
    )
  end

  def build_empty_type_catalog_tool
    stub_const("EmptyTypeCatalogTool", Class.new do
      include ActiveModel::Model
      include ToolPlugin

      def self.type_key = "empty_type_catalog_tool"
      def self.type_label = "Empty Type Catalog Tool"
      def self.type_icon = "fa-solid fa-wrench"
      def self.tool_designer_editable_attributes = []
      def self.tool_designer_actions = []
      def self.tool_designer_notes = []
    end,)
    EmptyTypeCatalogTool
  end

  # rubocop:disable Metrics/MethodLength
  def build_array_type_catalog_tool
    stub_const("ArrayTypeCatalogTool", Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations
      include ToolPlugin

      attribute :items, default: -> { [] }
      attribute :settings, default: -> { {} }
      attribute :required_field, :string
      attribute :mode, :string, default: "auto"
      attribute :count, :integer, default: 2
      attribute :limited_text, :string
      attribute :conditional_field, :string

      validates :required_field, presence: true
      validates :mode, inclusion: { in: ["auto", "manual"] }
      validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than: 5 }
      validates :limited_text, length: { maximum: 20 }
      validates :conditional_field, presence: true, if: -> { true }

      def self.type_key = "array_type_catalog_tool"
      def self.type_label = "Array Type Catalog Tool"
      def self.type_icon = "fa-solid fa-wrench"

      def self.tool_designer_editable_attributes
        [
          "items",
          "settings",
          "missing_field",
          "required_field",
          "mode",
          "count",
          "limited_text",
          "conditional_field",
        ]
      end

      def self.tool_designer_field_hints
        {
          "required_field" => resource_hint("custom_resources", note: "Fetch the exact ID first."),
        }
      end
    end,)
    ArrayTypeCatalogTool
  end
  # rubocop:enable Metrics/MethodLength

  def build_field_hint_edge_case_tool
    stub_const("FieldHintEdgeCaseTool", Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ToolPlugin

      attribute :string_hint, :string
      attribute :note_only_hint, :string
      attribute :ignored_hint, :string

      def self.type_key = "field_hint_edge_case_tool"
      def self.type_label = "Field Hint Edge Case Tool"
      def self.type_icon = "fa-solid fa-wrench"
      def self.tool_designer_editable_attributes = ["string_hint", "note_only_hint", "ignored_hint"]

      def self.tool_designer_field_hints
        {
          "string_hint" => "Literal hint.",
          "note_only_hint" => { "note" => "Only note." },
          "ignored_hint" => Object.new,
        }
      end
    end,)
    FieldHintEdgeCaseTool
  end

  def build_no_attribute_type_catalog_tool
    stub_const("NoAttributeTypeCatalogTool", Class.new do
      include ActiveModel::Model
      include ToolPlugin

      def self.type_key = "no_attribute_type_catalog_tool"
      def self.type_label = "No Attribute Type Catalog Tool"
      def self.type_icon = "fa-solid fa-wrench"
      def self.tool_designer_editable_attributes = ["manual_field"]
      def self.tool_designer_actions = []
    end,)
    NoAttributeTypeCatalogTool
  end

  around do |example|
    example.run
  ensure
    ToolPlugin.reset!
    UndercoverAgents::PluginSystem.register_tool_types!
  end

  it "returns empty helper collections for unknown tool types" do
    catalog = described_class.new("missing_tool")

    expect(catalog.editable_field_names).to eq([])
    expect(catalog.action_keys).to eq([])
  end

  it "returns action keys for known tool types" do
    expect(described_class.new("sql_query").action_keys).to include("discover", "set_visibility")
  end

  it "renders fallback sections when a tool type has no extra metadata" do
    empty_tool = build_empty_type_catalog_tool
    register_tool_type(empty_tool)
    allow(ToolPlugin).to receive(:all_types).and_return([])

    result = described_class.new(empty_tool.type_key).render

    expect(result).to include("- Description: None")
    expect(result).to include("## Type-Specific Editable Fields\n- None")
    expect(result).to include("## Supported Actions\n- None")
    expect(result).not_to include("## Notes")
  end

  it "renders array, value, and required field metadata", :aggregate_failures do
    array_tool = build_array_type_catalog_tool
    register_tool_type(array_tool, description: "Array-aware tool.")

    result = described_class.new(array_tool.type_key).render

    expect(result).to include("`items` (array, optional)")
    expect(result).to include("`settings` (object, optional)")
    expect(result).to include("`missing_field` (value, optional)")
    expect(result).to include("`mode` (string, optional) — Allowed values: `auto`, `manual`. Default: `auto`.")
    expect(result).to include("`count` (integer, optional) — Numeric constraint: integer, >= 1, < 5. Default: `2`.")
    expect(result).to include("`limited_text` (string, optional) — Maximum length: 20.")
    expect(result).to include("`conditional_field` (string, conditionally required)")
    expect(result).to include(
      "`required_field` (string, required) — Use list_resources(kind: \"custom_resources\") " \
      "to resolve exact IDs. Fetch the exact ID first.",
    )
  end

  it "renders editable fields for classes without ActiveModel attribute types" do
    no_attribute_tool = build_no_attribute_type_catalog_tool
    register_tool_type(no_attribute_tool, description: "Manual field tool.")

    result = described_class.new(no_attribute_tool.type_key).render

    expect(result).to include("`manual_field` (value, optional)")
  end

  it "renders action argument metadata" do
    result = described_class.new("sql_query").render

    expect(result).to include(
      "`set_visibility` — Update which discovered items stay visible to the runtime tool. " \
      "Arguments: `selected_items` (array, optional): " \
      "The complete desired list of discovered item names to expose.",
    )
  end

  it "renders action arguments without optional descriptions" do
    catalog = described_class.new("sql_query")

    expect(catalog.send(:action_arguments, "arguments" => [{ "name" => "limit" }])).to eq(
      " Arguments: `limit` (value, optional).",
    )
  end

  it "renders required action arguments" do
    catalog = described_class.new("sql_query")

    expect(catalog.send(:action_arguments, "arguments" => [{ "name" => "query", "required" => true }])).to eq(
      " Arguments: `query` (value, required).",
    )
  end

  it "renders string, note-only, and ignored field hints safely" do
    edge_case_tool = build_field_hint_edge_case_tool
    register_tool_type(edge_case_tool, description: "Field hint edge cases.")

    result = described_class.new(edge_case_tool.type_key).render

    expect(result).to include("`string_hint` (string, optional) — Literal hint.")
    expect(result).to include("`note_only_hint` (string, optional) — Only note.")
    expect(result).to include("`ignored_hint` (string, optional)")
  end
end
