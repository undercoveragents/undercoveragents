# frozen_string_literal: true

# == Schema Information
#
# Table name: tools
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  description   :text
#  enabled       :boolean          default(TRUE), not null
#  name          :string           not null
#  slug          :string           not null
#  tool_type     :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operation_id  :bigint           not null
#
# Indexes
#
#  index_tools_on_enabled                (enabled)
#  index_tools_on_operation_id           (operation_id)
#  index_tools_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_tools_on_slug                   (slug) UNIQUE
#  index_tools_on_tool_type              (tool_type)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
require "rails_helper"

RSpec.describe Tool do
  describe "validations" do
    subject { create(:tool, :sql_query) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:operation_id).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:description).is_at_most(500) }
  end

  describe "scopes" do
    let!(:enabled_tool) { create(:tool, :sql_query, :enabled) }
    let!(:disabled_tool) { create(:tool, :sql_query, :disabled) }

    describe ".enabled" do
      it "returns only enabled tools" do
        expect(described_class.enabled).to contain_exactly(enabled_tool)
      end
    end

    describe ".disabled" do
      it "returns only disabled tools" do
        expect(described_class.disabled).to contain_exactly(disabled_tool)
      end
    end

    describe ".ordered" do
      it "returns tools ordered by name" do
        expect(described_class.ordered).to eq(described_class.order(:name))
      end
    end

    describe ".by_type" do
      it "filters by tool type" do
        expect(described_class.by_type("sql_query")).to contain_exactly(enabled_tool, disabled_tool)
      end

      it "filters plugin-backed mission tools without dedicated scopes" do
        mission_tool = create(:tool, :mission_tool)

        expect(described_class.by_type("mission_tool")).to contain_exactly(mission_tool)
      end

      it "returns empty for unknown types" do
        expect(described_class.by_type("Tools::Unknown")).to be_empty
      end
    end
  end

  describe "amoeba deep clone" do
    context "when the original tool has a toolable" do
      it "copies configuration to the clone" do
        tool = create(:tool, :sql_query)
        clone = tool.amoeba_dup

        expect(clone.toolable).to be_a(Tools::SqlQuery)
        expect(clone.configuration).to eq(tool.configuration)
      end
    end

    context "when the original tool has no toolable (blank)" do
      it "skips toolable cloning and leaves the clone toolable unset" do
        tool = create(:tool, :sql_query)
        allow(tool).to receive(:toolable).and_return(nil)
        # amoeba_dup should complete without raising, skipping the deep clone
        expect { tool.amoeba_dup }.not_to raise_error
      end
    end
  end

  describe "plugin configurator behavior" do
    before do
      stub_const(
        "Tools::SpecConfig",
        Class.new do
          include UndercoverAgents::PluginSystem::Configurator
          include ToolPlugin

          attribute :answer, :integer
          validates :answer, presence: true

          def self.type_key = "spec_config"
          def self.type_label = "Spec Config"
          def self.type_icon = "fa-solid fa-flask"
        end,
      )

      next if ToolPlugin.type_keys.include?("spec_config")

      ToolPlugin.register(
        "spec_config",
        "Tools::SpecConfig",
        label: "Spec Config",
        icon: "fa-solid fa-flask",
        description: "Spec-only tool type",
      )
    end

    it "serializes non-AR configurator objects into configuration JSON" do
      tool = build(
        :tool,
        name: "Spec Tool",
        tool_type: "spec_config",
      )
      tool.configurator = Tools::SpecConfig.new(answer: 42)

      expect(tool.save).to be(true)
      expect(tool.reload.configuration).to eq({ "answer" => 42 })
    end

    it "propagates non-AR configurator validation errors" do
      tool = build(
        :tool,
        name: "Invalid Spec",
        tool_type: "spec_config",
      )
      tool.configurator = Tools::SpecConfig.new(answer: nil)

      expect(tool).not_to be_valid
      expect(tool.errors[:answer]).to include("can't be blank")
    end

    it "supports nil assignment in toolable writer" do
      tool = create(:tool, :sql_query)
      expect { tool.toolable = nil }.not_to raise_error
    end

    it "falls back to humanized labels/icons for unknown types" do
      tool = described_class.new(tool_type: "unknown", name: "Unknown Tool")

      expect(tool.type_label).to eq("Unknown")
      expect(tool.type_icon).to eq("fa-solid fa-wrench")
    end
  end

  describe "#configurator caching" do
    it "returns the same cached configurator on repeated access" do
      tool = create(:tool, :sql_query)
      first = tool.configurator
      second = tool.configurator
      expect(first).to equal(second)
    end

    it "rebuilds the configurator when tool_type changes" do
      tool = create(:tool, :sql_query)
      first = tool.configurator
      tool.tool_type = "rag_query"
      second = tool.configurator
      expect(second).not_to equal(first)
    end
  end

  describe "#type_label" do
    it "returns the registered label for the tool type" do
      tool = create(:tool, :sql_query)
      expect(tool.type_label).to eq("SQL Query")
    end

    it "falls back to humanized tool_type when label_for returns nil" do
      tool = build(:tool, :sql_query)
      allow(ToolPlugin).to receive(:label_for).and_return(nil)
      expect(tool.type_label).to eq("Sql query")
    end
  end

  describe "#type_icon" do
    it "returns the registered icon for the tool type" do
      tool = create(:tool, :sql_query)
      expect(tool.type_icon).to be_a(String)
    end

    it "falls back to default icon when icon_for returns nil" do
      tool = build(:tool, :sql_query)
      allow(ToolPlugin).to receive(:icon_for).and_return(nil)
      expect(tool.type_icon).to eq("fa-solid fa-wrench")
    end
  end

  describe "validation: tool_type_registered" do
    it "adds an error when tool_type is not a registered plugin" do
      tool = described_class.new(tool_type: "nonexistent_type", name: "Test Tool")
      expect(tool).not_to be_valid
      expect(tool.errors[:tool_type]).to include("is not a registered tool type")
    end

    it "skips validation when tool_type is blank" do
      tool = described_class.new(tool_type: "", name: "Blank Type")
      tool.valid?
      expect(tool.errors[:tool_type]).not_to include("is not a registered tool type")
    end
  end

  describe "#ensure_configuration" do
    it "sets configuration to {} when it is nil" do
      tool = described_class.new(tool_type: "sql_query", name: "Test Tool")
      tool.configuration = nil
      tool.valid?
      expect(tool.configuration).to eq({})
    end

    it "preserves configuration when it is already a Hash" do
      tool = described_class.new(tool_type: "sql_query", name: "Test Tool",
                                 configuration: { "key" => "value" },)
      tool.valid?
      expect(tool.configuration).to eq({ "key" => "value" })
    end
  end

  describe "#validate_configurator" do
    it "skips validation when configurator is nil" do
      tool = build(:tool, :sql_query)
      allow(tool).to receive(:configurator).and_return(nil)
      tool.valid?
      # No error propagation from nil configurator
      expect(tool.errors[:answer]).to be_empty
    end

    it "skips validation when configurator is persisted" do
      tool = create(:tool, :sql_query)
      persisted_cfg = tool.configurator
      allow(persisted_cfg).to receive(:persisted?).and_return(true)
      allow(tool).to receive(:configurator).and_return(persisted_cfg)
      # Should not propagate validation errors for persisted configurators
      expect(tool).to be_valid
    end

    it "propagates errors from invalid configurator" do
      tool = build(:tool, :sql_query)
      cfg = tool.configurator
      errors = ActiveModel::Errors.new(cfg)
      errors.add(:base, "test error from configurator")
      allow(cfg).to receive_messages(persisted?: false, valid?: false, errors:)
      allow(tool).to receive(:configurator).and_return(cfg)

      tool.valid?
      expect(tool.errors[:base]).to include("test error from configurator")
    end

    it "skips error propagation when configurator does not respond to persisted?" do
      tool = build(:tool, :sql_query)
      cfg = double("plain_configurator") # rubocop:disable RSpec/VerifiedDoubles
      allow(cfg).to receive(:respond_to?) do |method_name, *|
        [:valid?, :_tool_record=].include?(method_name)
      end
      allow(cfg).to receive(:_tool_record=)
      allow(cfg).to receive_messages(valid?: true, is_a?: false, to_configuration: {})
      allow(tool).to receive(:configurator).and_return(cfg)

      tool.valid?
      expect(tool.errors[:base]).to be_empty
    end
  end

  describe "#toolable=" do
    it "resolves type via ToolPlugin.key_for_class_name" do
      tool = create(:tool, :sql_query)
      sql_query = tool.toolable
      tool.toolable = sql_query
      expect(tool.tool_type).to eq("sql_query")
    end

    it "falls back to value.class.type_key when key_for_class_name returns nil" do
      tool = build(:tool, :sql_query)
      value = double("configurator") # rubocop:disable RSpec/VerifiedDoubles
      fake_class = double(name: "Unknown::Class", type_key: "custom_type", respond_to?: true)
      allow(value).to receive_messages(class: fake_class)
      allow(ToolPlugin).to receive(:key_for_class_name).with("Unknown::Class").and_return(nil)
      tool.toolable = value
      expect(tool.tool_type).to eq("custom_type")
    end

    it "sets nil tool_type when neither key_for_class_name nor type_key are available" do
      tool = build(:tool, :sql_query)
      klass = Class.new
      value = klass.new
      allow(ToolPlugin).to receive(:key_for_class_name).and_return(nil)
      tool.toolable = value
      expect(tool.tool_type).to be_nil
    end
  end

  describe "compatibility helpers" do
    it "delegates missing methods to the configurator when available" do
      tool = create(:tool, :sql_query)
      configurator = double("configurator", summary: "Summary") # rubocop:disable RSpec/VerifiedDoubles
      allow(tool).to receive(:configurator).and_return(configurator)

      expect(tool.summary).to eq("Summary")
    end

    it "raises NoMethodError when neither the tool nor configurator respond" do
      tool = create(:tool, :sql_query)

      expect { tool.nonexistent_method! }.to raise_error(NoMethodError)
    end

    it "exposes the configurator class name as toolable_type" do
      tool = create(:tool, :sql_query)

      expect(tool.toolable_type).to eq(tool.configurator.class.name)
    end

    it "returns nil for toolable_type when no configurator is available" do
      tool = build(:tool, :sql_query)
      allow(tool).to receive(:configurator).and_return(nil)

      expect(tool.toolable_type).to be_nil
    end

    it "returns record_id from either string or symbol keys" do
      tool = build(:tool, :sql_query, configuration: { record_id: 12 })

      expect(tool.toolable_id).to eq(12)
    end

    it "returns nil for toolable_id when configuration is not a hash" do
      tool = build(:tool, :sql_query)
      tool.configuration = nil

      expect(tool.toolable_id).to be_nil
    end
  end

  describe "private configurator builders" do
    it "loads record-backed configurators when record_id is present" do
      record = double("Record") # rubocop:disable RSpec/VerifiedDoubles
      klass = User
      allow(klass).to receive(:find_by).with(id: 123).and_return(record)
      tool = build(:tool, :sql_query, configuration: { "record_id" => 123 })

      expect(tool.send(:build_configurator_from, klass)).to eq(record)
    end

    it "returns nil for record-backed configurators when record_id is blank" do
      klass = User
      tool = build(:tool, :sql_query, configuration: {})

      expect(tool.send(:build_configurator_from, klass)).to be_nil
    end

    it "assigns _tool_record when building struct configurators" do
      klass = Class.new do
        attr_accessor :_tool_record, :attributes

        def initialize(attributes = {})
          @attributes = attributes
        end
      end
      tool = build(:tool, :sql_query, configuration: { "answer" => 42 })

      cfg = tool.send(:build_configurator_from, klass)

      expect(cfg._tool_record).to eq(tool)
      expect(cfg.attributes).to eq(answer: 42)
    end

    it "returns nil when a configurator class cannot be constructed" do
      tool = build(:tool, :sql_query)

      expect(tool.send(:build_configurator_from, Module.new)).to be_nil
    end

    it "does not assign _tool_record when the struct configurator does not support it" do
      klass = Class.new do
        attr_reader :attributes

        def initialize(attributes = {})
          @attributes = attributes
        end
      end
      tool = build(:tool, :sql_query, configuration: { "answer" => 42 })

      cfg = tool.send(:build_configurator_from, klass)

      expect(cfg.attributes).to eq(answer: 42)
    end
  end

  describe "#apply_configurator_before_save when configurator is an ApplicationRecord" do
    it "stores the record_id in configuration" do
      tool = create(:tool, :sql_query)
      user = create(:user)
      # Stub configurator to be an AR instance to cover the is_a?(ApplicationRecord) branch
      allow(tool).to receive(:configurator).and_return(user)

      tool.save!

      expect(tool.configuration).to eq({ "record_id" => user.id })
    end
  end

  describe "#apply_configurator_before_save with to_configuration" do
    it "uses to_configuration for struct configurators" do
      tool = create(:tool, :sql_query)
      cfg = double("struct_cfg") # rubocop:disable RSpec/VerifiedDoubles
      allow(cfg).to receive(:respond_to?) do |method_name, *|
        [:to_configuration, :persisted?, :valid?].include?(method_name)
      end
      allow(cfg).to receive_messages(is_a?: false, persisted?: true, valid?: true, to_configuration: { "key" => "val" })
      allow(tool).to receive(:configurator).and_return(cfg)

      tool.save!

      expect(tool.configuration).to eq({ "key" => "val" })
    end
  end

  describe "#apply_configurator_before_save _tool_record= assignment" do
    it "assigns _tool_record when configurator responds to it" do
      tool = create(:tool, :sql_query)
      cfg = double("struct_cfg") # rubocop:disable RSpec/VerifiedDoubles
      allow(cfg).to receive(:respond_to?) do |method_name, *|
        [:to_configuration, :_tool_record=, :persisted?, :valid?].include?(method_name)
      end
      allow(cfg).to receive_messages(is_a?: false, persisted?: true, valid?: true, to_configuration: { "k" => "v" })
      allow(cfg).to receive(:_tool_record=)
      allow(tool).to receive(:configurator).and_return(cfg)

      tool.save!

      expect(cfg).to have_received(:_tool_record=).with(tool)
    end
  end

  describe "#apply_configurator_before_save when configurator is nil" do
    it "does not raise" do
      tool = build(:tool, :sql_query)
      allow(tool).to receive(:configurator).and_return(nil)
      expect { tool.save! }.not_to raise_error
    end

    it "leaves configuration unchanged for configurators without serialization hooks" do
      tool = create(:tool, :sql_query)
      cfg = double("plain_cfg") # rubocop:disable RSpec/VerifiedDoubles
      allow(cfg).to receive(:respond_to?) do |method_name, *|
        [:_tool_record=, :persisted?, :valid?].include?(method_name)
      end
      allow(cfg).to receive_messages(is_a?: false, persisted?: true, valid?: true)
      allow(cfg).to receive(:_tool_record=)
      allow(tool).to receive(:configurator).and_return(cfg)

      expect { tool.save! }.not_to(change { tool.reload.configuration })
    end
  end

  describe "#configuration_value" do
    it "returns nil when configuration is not a hash" do
      tool = build(:tool, :sql_query)
      tool.configuration = nil

      expect(tool.send(:configuration_value, :record_id)).to be_nil
    end
  end

  describe "#configuration= resets cached configurator" do
    it "rebuilds the configurator after configuration changes" do
      tool = create(:tool, :sql_query)
      original_cfg = tool.configurator
      tool.configuration = { "connector_id" => 999 }
      # Configurator should be a new object instance
      expect(tool.configurator).not_to be(original_cfg)
    end
  end

  describe "#reload clears cached configurator" do
    it "rebuilds configurator after reload" do
      tool = create(:tool, :sql_query)
      tool.configurator # force build
      tool.reload
      # After reload, configurator is rebuilt from DB state
      expect(tool.configurator).to be_a(Tools::SqlQuery)
    end
  end
end
