# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Agent do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns agent" do
      expect(described_class.node_type).to eq("agent")
    end
  end

  describe ".node_category" do
    it "is llm" do
      expect(described_class.node_category).to eq(:llm)
    end
  end

  describe ".required_field_keys" do
    it "requires agent_id" do
      expect(described_class.required_field_keys).to eq(["agent_id"])
    end
  end

  describe ".variable_schema" do
    it "declares response output" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("response")
    end
  end

  describe ".extract_variables" do
    it "extracts template variables from prompt" do
      variables = []
      seen = Set.new
      data = { "prompt" => "Analyze {{data}}" }

      described_class.extract_variables(data, "Agent", variables, seen)

      expect(variables.pluck(:key)).to include("data")
    end
  end

  describe "#execute" do
    it "fails when no agent_id configured" do
      context.set_variable("_current_node_data", { "agent_id" => "" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Agent not configured")
    end

    it "fails when agent is not found" do
      context.set_variable("_current_node_data", { "agent_id" => "999", "prompt" => "test" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Agent not found")
    end

    it "fails when no prompt and no input" do
      agent = create(:agent)
      context.set_variable("_current_node_data", { "agent_id" => agent.id.to_s, "prompt" => "" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("no prompt and no input")
    end

    it "invokes agent with prompt and returns response" do
      agent = create(:agent)
      response = double(content: "Agent result")
      allow_any_instance_of(Agent).to receive(:ask).and_return(response) # rubocop:disable RSpec/AnyInstance

      context.set_variable("_current_node_data", {
                             "agent_id" => agent.id.to_s,
                             "prompt" => "Analyze this",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["response"]).to eq("Agent result")
    end

    it "interpolates prompt variables" do
      agent = create(:agent)
      response = double(content: "done")
      allow_any_instance_of(Agent).to receive(:ask).with("Analyze hello").and_return(response) # rubocop:disable RSpec/AnyInstance

      context.set_variable("data", "hello")
      context.set_variable("_current_node_data", {
                             "agent_id" => agent.id.to_s,
                             "prompt" => "Analyze {{data}}",
                           })

      result = node.execute(context)

      expect(result).to be_success
    end

    it "falls back to the current branch input when prompt is empty" do
      agent = create(:agent)
      response = double(content: "result")
      allow_any_instance_of(Agent).to receive(:ask).with("previous output").and_return(response) # rubocop:disable RSpec/AnyInstance

      context.current_input = "previous output"
      context.set_variable("_current_node_data", {
                             "agent_id" => agent.id.to_s,
                             "prompt" => "",
                           })

      result = node.execute(context)

      expect(result).to be_success
    end

    it "fails when agent returns empty response" do
      agent = create(:agent)
      allow_any_instance_of(Agent).to receive(:ask).and_return(double(content: nil)) # rubocop:disable RSpec/AnyInstance

      context.set_variable("_current_node_data", {
                             "agent_id" => agent.id.to_s,
                             "prompt" => "test",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("empty response")
    end

    it "catches unexpected errors" do
      agent = create(:agent)
      allow_any_instance_of(Agent).to receive(:ask).and_raise(StandardError, "boom") # rubocop:disable RSpec/AnyInstance

      context.set_variable("_current_node_data", {
                             "agent_id" => agent.id.to_s,
                             "prompt" => "test",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Agent error: boom")
    end
  end
end
