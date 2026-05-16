# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::MemoryPluginHooks do
  describe ".apply_agent_extension!" do
    it "includes the extension only once" do
      extension = Module.new
      agent_class = Class.new

      described_class.apply_agent_extension!(agent_class:, extension:)

      expect(agent_class < extension).to be(true)
      expect { described_class.apply_agent_extension!(agent_class:, extension:) }
        .not_to(change { agent_class.ancestors.count(extension) })
    end

    it "does not include the extension again when it is already present" do
      extension = Module.new
      agent_class = Class.new do
        include extension
      end

      allow(agent_class).to receive(:include).and_call_original

      described_class.apply_agent_extension!(agent_class:, extension:)

      expect(agent_class).not_to have_received(:include)
    end
  end

  describe "plugin reload hook" do
    let(:plugin_path) { Rails.root.join("plugins/capability_memory/plugin.rb").to_s }

    before do
      stub_const("Agent", Class.new(ApplicationRecord) do
        self.table_name = "agents"
      end,)

      allow(Rails.application.reloader).to receive(:to_prepare).and_yield
      allow(UndercoverAgents::PluginSystem).to receive(:register) do |identifier, &block|
        UndercoverAgents::PluginSystem::Definition.new(identifier).tap do |definition|
          definition.instance_eval(&block) if block
        end
      end
    end

    it "runs the to_prepare hook for the agent extension" do
      load plugin_path

      expect(Agent.ancestors).to include(Capabilities::Memory::AgentExtension)
    end

    it "invokes the memory plugin hook from the to_prepare callback" do
      allow(described_class).to receive(:apply_agent_extension!).and_call_original

      load plugin_path

      expect(described_class).to have_received(:apply_agent_extension!)
    end

    it "applies and then skips fresh agent extensions after the plugin reload hook runs" do
      load plugin_path
      extension = Module.new
      agent_class = Class.new

      allow(agent_class).to receive(:include).and_call_original

      described_class.apply_agent_extension!(agent_class:, extension:)
      described_class.apply_agent_extension!(agent_class:, extension:)

      expect(agent_class).to have_received(:include).with(extension).once
      expect(agent_class.ancestors).to include(extension)
    end

    it "does not include the agent extension twice when the plugin is reloaded" do
      load plugin_path

      expect do
        load plugin_path
      end.not_to(change { Agent.ancestors.count(Capabilities::Memory::AgentExtension) })
    end
  end
end
