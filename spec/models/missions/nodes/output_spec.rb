# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Output do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns output" do
      expect(described_class.node_type).to eq("output")
    end
  end

  describe ".node_category" do
    it "is input_output" do
      expect(described_class.node_category).to eq(:input_output)
    end
  end

  describe ".node_description" do
    it "describes the mission output" do
      expect(described_class.node_description).to include("output")
    end
  end

  describe ".variable_schema" do
    it "declares dynamic output" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("*")
      expect(names).to include("_output_meta")
    end

    it "declares config inputs through field contracts" do
      names = described_class.input_schema.pluck(:name)

      expect(names).to include("status", "status_code", "response_body")
    end
  end

  describe ".default_output_ports" do
    it "has no output ports (terminal node)" do
      expect(described_class.default_output_ports).to eq([])
    end
  end

  describe ".extract_variables" do
    it "extracts template variables from response_body" do
      variables = []
      seen = Set.new

      described_class.extract_variables(
        { "response_body" => '{"result": "{{result}}"}' },
        "Output", variables, seen,
      )

      expect(variables.pluck(:key)).to include("result")
    end

    it "does not extract variables when response_body is blank" do
      variables = []
      seen = Set.new

      described_class.extract_variables({}, "Output", variables, seen)

      expect(variables).to be_empty
    end
  end

  describe ".dynamic_output_variables" do
    it "parses selected variables from JSON strings and skips blanks" do
      outputs = described_class.dynamic_output_variables(
        "selected_variables" => '["response", "", "score"]',
      )

      expect(outputs).to contain_exactly(
        include(name: "response", description: "Selected output variable"),
        include(name: "score", description: "Selected output variable"),
      )
    end

    it "returns an empty array for malformed or missing selected variable payloads" do
      expect(described_class.dynamic_output_variables("selected_variables" => "{bad-json}")).to eq([])
      expect(described_class.dynamic_output_variables("selected_variables" => nil)).to eq([])
    end
  end

  describe "#execute" do
    it "outputs selected variables" do
      context.set_variable("response", "hello")
      context.set_variable("score", 0.9)
      context.set_variable("_current_node_data", {
                             "selected_variables" => ["response", "score"],
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["response"]).to eq("hello")
      expect(result.variables["score"]).to eq(0.9)
    end

    it "falls back to the current branch input when no variables selected" do
      context.current_input = "fallback result"
      context.set_variable("_current_node_data", { "selected_variables" => [] })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["output"]).to eq("fallback result")
    end

    it "falls back when selected_variables is nil" do
      context.current_input = "result"
      context.set_variable("_current_node_data", {})

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["output"]).to eq("result")
    end

    it "includes nil for missing selected variables" do
      context.set_variable("_current_node_data", {
                             "selected_variables" => ["missing_var"],
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["missing_var"]).to be_nil
    end

    it "sets selected variables on context" do
      context.set_variable("data", "value")
      context.set_variable("_current_node_data", {
                             "selected_variables" => ["data"],
                           })

      node.execute(context)

      expect(context.get_variable("data")).to eq("value")
    end

    it "defaults status to success and status_code to 200" do
      context.set_variable("_current_node_data", {})
      result = node.execute(context)

      meta = result.variables["_output_meta"]
      expect(meta["status"]).to eq("success")
      expect(meta["status_code"]).to eq(200)
    end

    it "uses configured status and status_code" do
      context.set_variable("_current_node_data", {
                             "status" => "error",
                             "status_code" => 400,
                           })
      result = node.execute(context)

      meta = result.variables["_output_meta"]
      expect(meta["status"]).to eq("error")
      expect(meta["status_code"]).to eq(400)
    end

    it "falls back to success for invalid status values" do
      context.set_variable("_current_node_data", { "status" => "invalid" })
      result = node.execute(context)

      meta = result.variables["_output_meta"]
      expect(meta["status"]).to eq("success")
    end

    it "interpolates variables in response_body" do
      context.set_variable("name", "Alice")
      context.set_variable("_current_node_data", {
                             "status" => "success",
                             "status_code" => 200,
                             "response_body" => '{"greeting": "Hello {{name}}"}',
                           })
      result = node.execute(context)

      meta = result.variables["_output_meta"]
      expect(meta["response_body"]).to eq('{"greeting": "Hello Alice"}')
    end

    it "omits response_body from meta when not configured" do
      context.set_variable("_current_node_data", {})
      result = node.execute(context)

      meta = result.variables["_output_meta"]
      expect(meta).not_to have_key("response_body")
    end

    it "stores _output_meta on context" do
      context.set_variable("_current_node_data", { "status" => "error", "status_code" => 500 })
      node.execute(context)

      meta = context.get_variable("_output_meta")
      expect(meta["status"]).to eq("error")
      expect(meta["status_code"]).to eq(500)
    end

    it "fails with invalid status_code" do
      context.set_variable("_current_node_data", { "status_code" => "not_a_number" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Invalid status code")
    end
  end
end
