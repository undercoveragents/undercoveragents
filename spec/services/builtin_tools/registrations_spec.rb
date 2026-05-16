# frozen_string_literal: true

require "rails_helper"

RSpec.describe BuiltinTools::Registrations do
  around do |example|
    original = BuiltinTools::Registry.definitions.dup
    BuiltinTools::Registry.definitions.clear
    example.run
  ensure
    BuiltinTools::Registry.definitions.clear
    BuiltinTools::Registry.definitions.merge!(original)
  end

  it "registers the agent and channel designer builtin tools" do
    described_class.register_all!

    expect(BuiltinTools::Registry.definition_for("agent_designer.manage_agent_action")&.runtime_name)
      .to eq("manage_agent_action")
    expect(BuiltinTools::Registry.definition_for("agent_designer.read_agent_chat")&.runtime_name)
      .to eq("read_agent_chat")
    expect(BuiltinTools::Registry.definition_for("agent_designer.debug_agent")&.runtime_name)
      .to eq("debug_agent")
    expect(BuiltinTools::Registry.definition_for("channel_designer.read_channel")&.runtime_name)
      .to eq("read_channel")
    expect(BuiltinTools::Registry.definition_for("channel_designer.manage_channel_action")&.runtime_name)
      .to eq("manage_channel_action")
  end

  it "registers the skill designer builtin tools" do
    described_class.register_all!

    expect(BuiltinTools::Registry.definition_for("skill_catalog_designer.read_skill")&.runtime_name)
      .to eq("read_skill")
    expect(BuiltinTools::Registry.definition_for("skill_catalog_designer.manage_skill")&.runtime_name)
      .to eq("manage_skill")
    expect(BuiltinTools::Registry.definition_for("skill_catalog_designer.manage_skill_catalog_action")&.runtime_name)
      .to eq("manage_skill_catalog_action")
  end

  it "registers the test suite designer builtin tools" do
    described_class.register_all!

    expect(BuiltinTools::Registry.definition_for("test_suite_designer.read_test_suite")&.runtime_name)
      .to eq("read_test_suite")
    expect(BuiltinTools::Registry.definition_for("test_suite_designer.manage_test_case")&.runtime_name)
      .to eq("manage_test_case")
    expect(BuiltinTools::Registry.definition_for("test_suite_designer.manage_test_suite_action")&.runtime_name)
      .to eq("manage_test_suite_action")
    expect(BuiltinTools::Registry.definition_for("test_suite_designer.read_test_suite_run")&.runtime_name)
      .to eq("read_test_suite_run")
  end
end
