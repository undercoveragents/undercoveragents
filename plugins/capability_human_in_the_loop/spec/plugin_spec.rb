# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::HumanInTheLoopPluginHooks do
  describe ".apply_tool_call_extension!" do
    it "prepends the extension only once" do
      extension = Module.new
      tool_call_class = Class.new

      described_class.apply_tool_call_extension!(tool_call_class:, extension:)

      expect(tool_call_class < extension).to be(true)
      expect { described_class.apply_tool_call_extension!(tool_call_class:, extension:) }
        .not_to(change { tool_call_class.ancestors.count(extension) })
    end

    it "returns early when the extension is already present" do
      extension = Module.new
      tool_call_class = Class.new
      tool_call_class.prepend(extension)

      allow(tool_call_class).to receive(:prepend).and_call_original

      described_class.apply_tool_call_extension!(tool_call_class:, extension:)

      expect(tool_call_class).not_to have_received(:prepend)
    end

    it "returns without prepending when the compatibility check reports the extension is already included" do
      extension = Module.new
      tool_call_class = class_double(Class, :< => true)

      allow(tool_call_class).to receive(:prepend)

      described_class.apply_tool_call_extension!(tool_call_class:, extension:)

      expect(tool_call_class).not_to have_received(:prepend)
    end
  end

  describe "plugin reload hook" do
    let(:plugin_path) { Rails.root.join("plugins/capability_human_in_the_loop/plugin.rb").to_s }

    before do
      stub_const("ToolCall", Class.new(ApplicationRecord) do
        self.table_name = "tool_calls"
      end,)

      allow(Rails.application.reloader).to receive(:to_prepare).and_yield
      allow(UndercoverAgents::PluginSystem).to receive(:register) do |identifier, &block|
        UndercoverAgents::PluginSystem::Definition.new(identifier).tap do |definition|
          definition.instance_eval(&block) if block
        end
      end
    end

    it "prepends the tool call extension during the to_prepare hook" do
      load plugin_path

      expect(ToolCall.ancestors).to include(Capabilities::HumanInTheLoop::ToolCallExtension)
    end

    it "prepends extensions for fresh classes after the plugin reload hook runs" do
      load plugin_path
      extension = Module.new
      tool_call_class = Class.new

      allow(tool_call_class).to receive(:prepend).and_call_original

      described_class.apply_tool_call_extension!(tool_call_class:, extension:)

      expect(tool_call_class).to have_received(:prepend).with(extension)
      expect(tool_call_class.ancestors).to include(extension)
    end

    it "does not prepend the tool call extension twice when the plugin is reloaded" do
      load plugin_path

      expect do
        load plugin_path
      end.not_to(change { ToolCall.ancestors.count(Capabilities::HumanInTheLoop::ToolCallExtension) })
    end
  end
end
