# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::DebugAgentTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, tenant:, role: :admin) }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user:,
      tenant:,
      operation:,
    )
  end

  it "runs a synchronous debug chat and returns the created chat details" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    chat = build_stubbed(:chat, id: 123, agent:, user:, execution_context: :system, title: "Agent debug: Debugger")
    formatter = instance_double(AgentDesigner::ChatDebugFormatter, format_chat: "formatted chat")

    allow(agent).to receive(:build_chat).and_return(chat)
    allow(chat).to receive(:ask).with("Why did you answer that?").and_return("Because the tool result said so.")
    allow(AgentDesigner::ChatDebugFormatter).to receive(:new).with(agent:).and_return(formatter)

    result = described_class.new(runtime_context:, current_agent: agent).execute(prompt: "Why did you answer that?")

    expect(agent).to have_received(:build_chat).with(
      parent_chat: nil,
      execution_context: :system,
      user:,
      title: "Agent debug: Debugger",
      input_values: {},
      runtime_context: runtime_context.to_h,
    )
    expect(result).to include("Agent debug chat completed.")
    expect(result).to include("- Chat ID: `123`")
    expect(result).to include("Because the tool result said so.")
    expect(result).to include("formatted chat")
  end

  it "rejects blank prompts" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")

    result = described_class.new(runtime_context:, current_agent: agent).execute(prompt: "  ")

    expect(result).to eq("Error: prompt is required.")
  end

  it "validates input_values JSON" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")

    result = described_class.new(runtime_context:, current_agent: agent)
                            .execute(prompt: "Test", input_values: "[]")

    expect(result).to eq("Error: input_values must be a JSON object.")
  end

  it "returns a helpful message when there is no current agent" do
    result = described_class.new(runtime_context:).execute(prompt: "Test")

    expect(result).to eq(
      "No current agent is available. Pass agent_id after creating one or open an agent page first.",
    )
  end

  it "rescues malformed input_values JSON" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")

    result = described_class.new(runtime_context:, current_agent: agent)
                            .execute(prompt: "Test", input_values: "{")

    expect(result).to start_with("Error: Invalid JSON for input_values:")
  end

  it "rescues unexpected debug failures" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    chat = build_stubbed(:chat, id: 456, agent:, user:, execution_context: :system, title: "Agent debug: Debugger")

    allow(agent).to receive(:build_chat).and_return(chat)
    allow(chat).to receive(:ask).and_raise(StandardError, "boom")

    result = described_class.new(runtime_context:, current_agent: agent).execute(prompt: "Test")

    expect(result).to eq("Error debugging agent: boom")
  end

  it "normalizes hash and parameters input values" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    tool = described_class.new(runtime_context:, current_agent: agent)
    params = ActionController::Parameters.new(foo: "bar")

    expect(tool.send(:parse_json_object, { foo: "bar" }, field_name: "input_values")).to eq("foo" => "bar")
    expect(tool.send(:parse_json_object, params, field_name: "input_values")).to eq("foo" => "bar")
  end

  it "returns blank and truncated previews" do
    tool = described_class.new(runtime_context:)
    long_response = "x" * 181

    expect(tool.send(:preview, "   ")).to eq("None.")
    expect(tool.send(:preview, long_response)).to end_with("...")
  end
end
