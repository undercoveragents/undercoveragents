# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolPlugin do
  def with_test_tool(key, klass_name, **opts)
    described_class.register(key, klass_name, label: opts.fetch(:label, "Test Label"),
                                              icon: opts.fetch(:icon, "fa-solid fa-wrench"),
                                              description: opts.fetch(:description, "Test description"),)
    yield
  ensure
    described_class.reset!
    UndercoverAgents::PluginSystem.register_tool_types!
  end

  def build_stateful_tool_plugin
    stub_const("StatefulToolPlugin", Class.new do
      include ToolPlugin

      def self.tool_designer_state_attributes
        [
          tool_designer_state_attribute(label: "Status", method: :status),
          tool_designer_state_attribute(label: "Items", method: :items, empty: true),
          { "method" => "fallback_label" },
          tool_designer_state_attribute(label: "Blank", method: :blank_value),
          tool_designer_state_attribute(label: "Missing", method: :missing_value),
        ]
      end

      def status = "ready"
      def items = []
      def fallback_label = "fallback"
      def blank_value = nil
    end,)
    StatefulToolPlugin
  end

  describe ".register" do
    it "raises ArgumentError when registering the same key with a different class" do
      with_test_tool("test_dup_tool", "SomeClass") do
        expect do
          described_class.register("test_dup_tool", "AnotherClass", label: "X", icon: "X")
        end.to raise_error(ArgumentError, /already registered/)
      end
    end

    it "is idempotent when registering the same key and class again" do
      with_test_tool("test_idem_tool", "SameToolClass") do
        expect do
          described_class.register("test_idem_tool", "SameToolClass", label: "L", icon: "I")
        end.not_to raise_error
      end
    end
  end

  describe ".reset!" do
    it "clears all registered type maps" do
      # Capture original state of all maps before reset
      original_type_map = described_class.instance_variable_get(:@type_map).dup
      original_label_map = described_class.instance_variable_get(:@label_map).dup
      original_icon_map = described_class.instance_variable_get(:@icon_map).dup
      original_desc_map = described_class.instance_variable_get(:@description_map).dup

      described_class.reset!

      expect(described_class.type_map).to eq({})
      expect(described_class.label_for("sql_query")).to be_nil
    ensure
      # Restore all maps so other specs are not affected
      described_class.instance_variable_set(:@type_map, original_type_map)
      described_class.instance_variable_set(:@label_map, original_label_map)
      described_class.instance_variable_set(:@icon_map, original_icon_map)
      described_class.instance_variable_set(:@description_map, original_desc_map)
    end
  end

  describe ".type_map" do
    it "returns a copy of the registered type map" do
      UndercoverAgents::PluginSystem.register_tool_types! if described_class.type_map.empty?

      type_map = described_class.type_map
      expect(type_map).to be_a(Hash)
      expect(type_map).to include("sql_query", "mcp_server")
    end

    it "returns a duplicate (not the internal hash)" do
      map1 = described_class.type_map
      map2 = described_class.type_map
      expect(map1).not_to be(map2)
    end
  end

  describe ".all_types" do
    it "skips tool types whose plugin registry entry is disabled" do
      with_test_tool("disabled_tool", "DisabledTool") do
        fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [])
        allow(fake_registry).to receive(:enabled?).and_return(false)
        allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(fake_registry)

        expect(described_class.all_types).to eq([])
      end
    end
  end

  describe "registry recovery" do
    it "re-registers tool types from plugin manifests when resolving after reset" do
      described_class.reset!

      expect(described_class.resolve("sql_query")).to eq(Tools::SqlQuery)
      expect(described_class.all_types.pluck(:key)).to include("sql_query", "mcp_server")
    end

    it "returns nil when the plugin system is unavailable during recovery" do
      described_class.reset!
      hide_const("UndercoverAgents")

      expect(described_class.resolve("sql_query")).to be_nil
    end

    it "returns nil when the plugin registry has no loaded definitions" do
      described_class.reset!
      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, empty?: true)

      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(fake_registry)

      expect(described_class.resolve("sql_query")).to be_nil
    end

    it "swallows recovery errors and returns nil" do
      described_class.reset!
      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, empty?: false)

      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(fake_registry)
      allow(UndercoverAgents::PluginSystem).to receive(:register_tool_types!).and_raise(StandardError, "boom")

      expect(described_class.resolve("sql_query")).to be_nil
    end
  end

  describe "default included class methods" do
    # Create a minimal class that includes ToolPlugin without overriding the defaults.
    let(:klass) do
      stub_const("MinimalToolPlugin", Class.new do
        include ToolPlugin

        def initialize(*); end
      end,)
      MinimalToolPlugin
    end

    let(:attribute_aware_klass) do
      stub_const("AttributeAwareToolPlugin", Class.new do
        include ActiveModel::Model
        include ActiveModel::Attributes
        include ToolPlugin

        attribute :connector_id, :integer
        attribute :tool_widget_icon, :string
      end,)
      AttributeAwareToolPlugin
    end

    let(:designer_action_klass) do
      stub_const("DesignerActionToolPlugin", Class.new do
        include ToolPlugin

        attr_accessor :analysis_error, :discoveries, :instruction_error, :selected_items

        def initialize
          @discoveries = 0
        end

        def self.type_label = "Designer Action"

        def perform_discovery!
          self.discoveries += 1
          ToolPlugin::Result.new(success?: true, message: "Discovered")
        end

        def update_visibility!(raw_params)
          self.selected_items = raw_params.dig(:designer_action_tool_plugin, :selected_items)
        end

        def visibility_param_key = "selected_items"

        def validate_and_enqueue_analysis = analysis_error

        def validate_and_enqueue_instruction_generation = instruction_error
      end,)
      DesignerActionToolPlugin
    end

    describe ".type_key" do
      it "returns the underscored demodulized class name" do
        expect(klass.type_key).to eq("minimal_tool_plugin")
      end
    end

    describe ".type_label" do
      it "returns the titleized demodulized class name" do
        expect(klass.type_label).to eq("Minimal Tool Plugin")
      end
    end

    describe ".type_icon" do
      it "returns the default wrench icon" do
        expect(klass.type_icon).to eq("fa-solid fa-wrench")
      end
    end

    describe ".tool_widget_default_presentation" do
      it "returns a basic presentation using the provided display name and icon" do
        presentation = klass.tool_widget_default_presentation(
          display_name: "Widget Tool",
          icon: "fa-solid fa-bolt",
        )

        expect(presentation).to have_attributes(
          display_name: "Widget Tool",
          icon: "fa-solid fa-bolt",
        )
      end
    end

    describe ".permitted_params" do
      it "returns an empty array" do
        expect(klass.permitted_params).to eq([])
      end
    end

    describe ".build_from_params" do
      it "instantiates the class with permitted params" do
        instance = klass.build_from_params(ActionController::Parameters.new)
        expect(instance).to be_a(klass)
      end
    end

    describe ".tool_designer_editable_attributes" do
      it "returns an empty array when the class does not expose attribute_names" do
        expect(klass.tool_designer_editable_attributes).to eq([])
      end

      it "returns stringified attribute names when available" do
        expect(attribute_aware_klass.tool_designer_editable_attributes).to include("connector_id", "tool_widget_icon")
      end
    end

    describe ".tool_designer_notes" do
      it "returns an empty array by default" do
        expect(klass.tool_designer_notes).to eq([])
      end
    end

    describe ".tool_designer_field_hints" do
      it "returns an empty hash by default" do
        expect(klass.tool_designer_field_hints).to eq({})
      end
    end

    describe ".tool_designer_resource_kinds" do
      it "returns an empty array by default" do
        expect(klass.tool_designer_resource_kinds).to eq([])
      end
    end

    describe ".tool_designer_state_attributes" do
      it "returns an empty array by default" do
        expect(klass.tool_designer_state_attributes).to eq([])
      end
    end

    describe ".tool_designer_state_attribute" do
      it "builds a state attribute definition" do
        expect(klass.tool_designer_state_attribute(label: "Status", method: :status, empty: true)).to eq(
          "label" => "Status",
          "method" => "status",
          "empty" => true,
        )
      end
    end

    describe ".resource_hint" do
      it "builds a resource lookup hint hash" do
        expect(klass.resource_hint("custom_resources", note: "Fetch exact IDs.")).to eq(
          "resource_kind" => "custom_resources",
          "note" => "Fetch exact IDs.",
        )
      end
    end

    describe ".tool_designer_resource_kind" do
      it "builds a resource kind definition hash" do
        expect(
          klass.tool_designer_resource_kind(
            kind: "custom_resources",
            title: "Custom Resources",
            model_name: "CustomResource",
            scope: "operation_owned",
          ),
        ).to eq(
          "kind" => "custom_resources",
          "title" => "Custom Resources",
          "model_name" => "CustomResource",
          "scope" => "operation_owned",
        )
      end
    end

    describe ".tool_designer_actions" do
      it "returns no actions for the default implementation" do
        expect(klass.tool_designer_actions).to eq([])
      end

      it "returns supported actions with arguments and policy metadata" do
        actions = designer_action_klass.tool_designer_actions

        expect(actions.map { |action| action.fetch("key") }).to eq(
          ["discover", "set_visibility", "analyze_schema", "generate_instructions"],
        )
        expect(actions.second.fetch("arguments")).to include(
          hash_including("name" => "selected_items", "type" => "array"),
        )
        expect(designer_action_klass.tool_designer_action_policy_query("discover")).to eq(:discover_schema?)
        expect(designer_action_klass.tool_designer_action_definition("missing")).to be_nil
      end

      it "builds custom actions without policy metadata" do
        expect(klass.tool_designer_action(key: :custom, description: "Custom action.")).to eq(
          "key" => "custom",
          "description" => "Custom action.",
          "arguments" => [],
        )
      end
    end

    describe ".runtime_tool_adapter_class_name" do
      it "returns nil by default" do
        expect(klass.runtime_tool_adapter_class_name).to be_nil
      end
    end

    describe ".build_runtime_tool" do
      it "returns nil when no runtime adapter is configured" do
        expect(klass.build_runtime_tool(Object.new)).to be_nil
      end
    end

    describe ".tool_runtime_name" do
      it "returns nil when the tool record is missing" do
        expect(klass.tool_runtime_name(tool_record: nil)).to be_nil
      end
    end

    describe ".tool_runtime_names" do
      it "returns an empty array when no runtime name can be derived" do
        expect(klass.tool_runtime_names(tool_record: nil)).to eq([])
      end
    end

    describe ".tool_runtime_display_name" do
      it "returns nil when the tool record is missing" do
        expect(klass.tool_runtime_display_name(runtime_name: "missing_tool", tool_record: nil)).to be_nil
      end
    end

    describe "#visibility_param_key" do
      it "returns nil by default" do
        expect(klass.new.visibility_param_key).to be_nil
      end
    end

    describe "#tool_designer_state" do
      it "renders only plugin-declared state entries with values or empty visibility" do
        expect(build_stateful_tool_plugin.new.tool_designer_state).to eq(
          [
            { "label" => "Status", "value" => "ready" },
            { "label" => "Items", "value" => [] },
            { "label" => "Fallback label", "value" => "fallback" },
          ],
        )
      end
    end

    describe "#perform_tool_designer_action!" do
      it "runs generic actions through the plugin protocol" do
        tool = designer_action_klass.new

        expect(tool.perform_tool_designer_action!("discover")).to eq(
          ToolPlugin::Result.new(success?: true, message: "Discovered"),
        )
        expect(tool.discoveries).to eq(1)

        visibility_result = tool.perform_tool_designer_action!(
          "set_visibility",
          { selected_items: ["users"] },
        )
        expect(visibility_result).to eq(
          ToolPlugin::Result.new(success?: true, message: I18n.t("tools.visibility_updated")),
        )
        expect(tool.selected_items).to eq(["users"])
      end

      it "wraps queued action errors and successes" do
        tool = designer_action_klass.new

        expect(tool.perform_tool_designer_action!("analyze_schema")).to eq(
          ToolPlugin::Result.new(success?: true, message: I18n.t("tools.schema_analysis_started")),
        )

        tool.instruction_error = "Missing analysis"
        expect(tool.perform_tool_designer_action!("generate_instructions")).to eq(
          ToolPlugin::Result.new(success?: false, message: "Missing analysis"),
        )
      end

      it "rejects unsupported and unimplemented declared actions" do
        stub_const("CustomDesignerActionToolPlugin", Class.new do
          include ToolPlugin

          def self.type_label = "Custom Designer Action"

          def self.tool_designer_action_definitions
            [tool_designer_action(key: "custom", description: "Custom action.")]
          end
        end,)

        expect(CustomDesignerActionToolPlugin.tool_designer_action_policy_query("custom")).to be_nil
        expect { klass.new.perform_tool_designer_action!("discover") }
          .to raise_error(ArgumentError, "Action 'discover' is not supported for Minimal Tool Plugin.")
        expect { CustomDesignerActionToolPlugin.new.perform_tool_designer_action!("custom") }
          .to raise_error(
            NotImplementedError,
            "Action 'custom' is declared but not implemented by Custom Designer Action.",
          )
      end
    end
  end

  describe "#tool" do
    it "looks up the persisted tool record for a saved configurator" do
      stub_const("PersistedToolPlugin", Class.new do
        include ToolPlugin

        attr_accessor :id

        def initialize(id)
          @id = id
        end
      end,)

      configurator = PersistedToolPlugin.new(123)
      tool = Tool.new(
        operation: OperationFactoryHelper.default_operation,
        name: "Persisted Tool #{SecureRandom.hex(4)}",
        slug: "persisted-tool-#{SecureRandom.hex(4)}",
        tool_type: PersistedToolPlugin.type_key,
        enabled: true,
        configuration: { "record_id" => configurator.id.to_s },
      )
      tool.save!(validate: false)

      expect(configurator.tool).to eq(tool)
    end
  end
end
