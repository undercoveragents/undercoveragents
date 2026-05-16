# frozen_string_literal: true

require "rails_helper"

RSpec.describe HasCapabilities do
  let(:agent) { create(:agent) }

  def enable_capability(agent, key, config = {}, enabled: true)
    agent.set_capability_config(key, config, enabled:)
    agent.save!
  end

  describe ".capability_types" do
    it "returns a symbolized hash of registered capability type keys to class names" do
      types = Agent.capability_types
      expect(types).to be_a(Hash)
      expect(types).to include(chat_title_generator: "Capabilities::TitleGenerator")
    end
  end

  describe "#capability" do
    it "returns a capability instance for a known key" do
      cap = agent.capability(:chat_title_generator)
      expect(cap).to be_a(Capabilities::TitleGenerator)
    end

    it "returns nil for an unknown key" do
      expect(agent.capability(:nonexistent)).to be_nil
    end

    it "returns defaults when no capability config exists" do
      cap = agent.capability(:chat_title_generator)
      expect(cap.max_length).to eq(Capabilities::TitleGenerator::DEFAULT_MAX_LENGTH)
      expect(cap.max_turns).to eq(Capabilities::TitleGenerator::DEFAULT_MAX_TURNS)
    end

    it "returns stored config values from the configuration" do
      enable_capability(agent, "chat_title_generator", {
                          "max_length" => 50,
                          "max_turns" => 3,
                          "llm_config_source" => "inherit",
                          "temperature" => 0.7,
                        })
      agent.reload
      cap = agent.capability(:chat_title_generator)
      expect(cap.max_length).to eq(50)
    end
  end

  describe "#capability_enabled?" do
    it "returns false when capability config does not exist" do
      expect(agent.capability_enabled?(:chat_title_generator)).to be false
    end

    it "returns true when capability is configured and enabled" do
      enable_capability(agent, "chat_title_generator")
      expect(agent.capability_enabled?(:chat_title_generator)).to be true
    end

    it "returns false when capability is configured but disabled" do
      enable_capability(agent, "chat_title_generator", {}, enabled: false)
      expect(agent.capability_enabled?(:chat_title_generator)).to be false
    end

    it "returns false for unknown capabilities" do
      expect(agent.capability_enabled?(:nonexistent)).to be false
    end
  end

  describe "#configured_capabilities" do
    it "returns empty when no capabilities are enabled" do
      expect(agent.configured_capabilities).to be_empty
    end

    it "returns enabled capability entries" do
      enable_capability(agent, "chat_title_generator")
      caps = agent.configured_capabilities
      expect(caps.size).to eq(1)
      expect(caps.first).to be_a(HasCapabilities::CapabilityEntry)
      expect(caps.first.configurator).to be_a(Capabilities::TitleGenerator)
    end

    it "excludes disabled capabilities" do
      enable_capability(agent, "chat_title_generator", {}, enabled: false)
      expect(agent.configured_capabilities).to be_empty
    end

    it "exposes type_label on entries" do
      enable_capability(agent, "chat_title_generator")
      entry = agent.configured_capabilities.first
      expect(entry.type_label).to be_a(String)
    end
  end

  describe "#remove_capability_config" do
    it "removes a previously stored capability" do
      enable_capability(agent, "chat_title_generator")
      expect(agent.capability_enabled?(:chat_title_generator)).to be true

      agent.remove_capability_config(:chat_title_generator)
      agent.save!

      expect(agent.capability_enabled?(:chat_title_generator)).to be false
    end
  end

  describe "CapabilityEntry#method_missing" do
    it "raises NoMethodError for methods not on configurator" do
      enable_capability(agent, "chat_title_generator")
      entry = agent.configured_capabilities.first
      expect { entry.totally_nonexistent_method }.to raise_error(NoMethodError)
    end

    it "returns true for respond_to? on configurator methods" do
      enable_capability(agent, "chat_title_generator")
      entry = agent.configured_capabilities.first
      expect(entry.respond_to?(:max_length)).to be true
    end

    it "returns false for respond_to? on unknown methods" do
      enable_capability(agent, "chat_title_generator")
      entry = agent.configured_capabilities.first
      expect(entry.respond_to?(:totally_nonexistent_method)).to be false
    end
  end

  describe "CapabilityEntry#resolve_configurator" do
    it "returns nil when configurator class raises an error" do
      agent.set_capability_config("chat_title_generator", { "bad_key" => "value" }, enabled: true)
      agent.save!

      allow(CapabilityPlugin).to receive(:resolve).with("chat_title_generator").and_raise(StandardError)

      entry = agent.configured_capabilities.first
      expect(entry.configurator).to be_nil
    end
  end

  describe "#capability_tools" do
    let(:user) { create(:user) }

    context "when there are no enabled capabilities" do
      it "returns an empty array" do
        expect(agent.capability_tools).to eq([])
      end
    end

    context "when an enabled capability provides tools" do
      before do
        enable_capability(agent, "memory", {
                            "model_id" => "text-embedding-3-small",
                            "embedding_dimensions" => 1536,
                            "auto_bootstrap" => true,
                          })
        Capabilities::Memory::Bootstrapper.new(agent, user:).bootstrap!
      end

      it "returns tools contributed by the capability" do
        chat = instance_double(Chat, user:)
        tools = agent.capability_tools(parent_chat: chat)
        expect(tools.map(&:name)).to include("memory_replace", "memory_insert")
      end
    end

    context "when an enabled capability does not respond to tools_for" do
      before do
        enable_capability(agent, "memory", {
                            "model_id" => "text-embedding-3-small",
                            "embedding_dimensions" => 1536,
                            "auto_bootstrap" => true,
                          })
      end

      it "skips it and returns an empty array" do
        configurator = instance_double(Capabilities::Memory)
        allow(configurator).to receive(:respond_to?).with(:tools_for).and_return(false)
        allow_any_instance_of(HasCapabilities::CapabilityEntry).to receive(:configurator).and_return(configurator) # rubocop:disable RSpec/AnyInstance

        expect(agent.capability_tools).to eq([])
      end
    end

    context "when an enabled capability raises inside tools_for" do
      before do
        enable_capability(agent, "memory", {
                            "model_id" => "text-embedding-3-small",
                            "embedding_dimensions" => 1536,
                            "auto_bootstrap" => true,
                          })
      end

      it "rescues the error, logs it, and returns an empty array" do
        configurator = instance_double(Capabilities::Memory)
        allow(configurator).to receive(:respond_to?).with(:tools_for).and_return(true)
        allow(configurator).to receive(:tools_for).and_raise(StandardError, "boom")
        allow_any_instance_of(HasCapabilities::CapabilityEntry).to receive(:configurator).and_return(configurator) # rubocop:disable RSpec/AnyInstance
        allow(Rails.logger).to receive(:error)

        expect(agent.capability_tools).to eq([])
        expect(Rails.logger).to have_received(:error).with(/tools_for failed/)
      end
    end
  end

  describe "#capability_system_prompt_additions" do
    let(:user) { create(:user) }

    context "when there are no enabled capabilities" do
      it "returns an empty array" do
        expect(agent.capability_system_prompt_additions(user:)).to eq([])
      end
    end

    context "when an enabled capability provides a system prompt addition" do
      before do
        enable_capability(agent, "memory", {
                            "model_id" => "text-embedding-3-small",
                            "embedding_dimensions" => 1536,
                            "auto_bootstrap" => true,
                          })
        Capabilities::Memory::Bootstrapper.new(agent, user:).bootstrap!
      end

      it "includes the memory blocks XML in the result" do
        additions = agent.capability_system_prompt_additions(user:)
        expect(additions).to all(be_a(String))
        expect(additions.first).to include("<memory_blocks>")
      end
    end

    context "when an enabled capability does not respond to system_prompt_addition_for" do
      before do
        enable_capability(agent, "memory", {
                            "model_id" => "text-embedding-3-small",
                            "embedding_dimensions" => 1536,
                            "auto_bootstrap" => true,
                          })
      end

      it "skips it and returns an empty array" do
        configurator = instance_double(Capabilities::Memory)
        allow(configurator).to receive(:respond_to?).with(:system_prompt_addition_for).and_return(false)
        allow_any_instance_of(HasCapabilities::CapabilityEntry).to receive(:configurator).and_return(configurator) # rubocop:disable RSpec/AnyInstance

        expect(agent.capability_system_prompt_additions(user:)).to eq([])
      end
    end

    context "when an enabled capability raises inside system_prompt_addition_for" do
      before do
        enable_capability(agent, "memory", {
                            "model_id" => "text-embedding-3-small",
                            "embedding_dimensions" => 1536,
                            "auto_bootstrap" => true,
                          })
      end

      it "rescues the error, logs it, and returns nil (filtered out)" do
        configurator = instance_double(Capabilities::Memory)
        allow(configurator).to receive(:respond_to?).with(:system_prompt_addition_for).and_return(true)
        allow(configurator).to receive(:system_prompt_addition_for).and_raise(StandardError, "crash")
        allow_any_instance_of(HasCapabilities::CapabilityEntry).to receive(:configurator).and_return(configurator) # rubocop:disable RSpec/AnyInstance
        allow(Rails.logger).to receive(:error)

        expect(agent.capability_system_prompt_additions(user:)).to eq([])
        expect(Rails.logger).to have_received(:error).with(/system_prompt_addition_for failed/)
      end
    end
  end

  describe "edge cases for branch coverage" do
    it "resolve_configurator returns nil for an unknown capability type in config" do
      agent.set_capability_config("totally_unknown_cap", { "foo" => "bar" }, enabled: true)
      agent.save!

      entries = agent.configured_capabilities
      unknown = entries.find { |e| e.capability_type == "totally_unknown_cap" }
      expect(unknown).not_to be_nil
      expect(unknown.configurator).to be_nil
    end

    it "configured_capabilities skips non-Hash entries in capabilities config" do
      agent.configuration = agent.configuration.merge(
        "capabilities" => {
          "chat_title_generator" => "not_a_hash",
          "valid_one" => { "enabled" => true },
        },
      )
      agent.save!(validate: false)

      caps = agent.configured_capabilities
      expect(caps.map(&:capability_type)).not_to include("chat_title_generator")
    end

    it "capabilities_hash returns empty hash when configuration is not a Hash" do
      agent.save!
      # Bypass validations and write a non-Hash configuration directly
      agent.update_columns(configuration: "not_a_hash") # rubocop:disable Rails/SkipsModelValidations
      agent.reload

      expect(agent.configured_capabilities).to eq([])
    end
  end
end
