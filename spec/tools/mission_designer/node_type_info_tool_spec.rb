# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::NodeTypeInfoTool do
  let(:tool) { described_class.new }

  describe "#name" do
    it "returns get_node_type_info" do
      expect(tool.name).to eq("get_node_type_info")
    end
  end

  describe "tool description" do
    it "directs unknown-variable debugging to list_node_variables" do
      expect(described_class.description)
        .to include("It does not tell you live variable names; use list_node_variables")
    end
  end

  describe "#execute" do
    it "requires either node_type or node_types" do
      expect(tool.execute).to include("Provide node_type or node_types")
    end

    it "returns detailed instructions for a known type" do
      result = tool.execute(node_type: "llm")
      expect(result).to include("LLM", "connector_id", "model", "tool_ids")
    end

    it "returns multiple node type descriptions in one call" do
      result = tool.execute(node_types: ["llm", "agent"])

      expect(result).to include("type: \"llm\"")
      expect(result).to include("## Agent (type: \"agent\")")
      expect(result).to include("list_resources(kinds: ['llm_connectors', 'default_models', 'tools'])")
      expect(result).to include("list_resources(kinds: ['agents'])")
    end

    it "returns instructions for input type" do
      result = tool.execute(node_type: "input")
      expect(result).to include("fields")
      expect(result).to include("variable_name")
    end

    it "returns custom instructions for condition type" do
      result = tool.execute(node_type: "condition")
      expect(result).to include("expression", "true", "false", "Runtime Branch Pruning")
    end

    it "returns custom instructions for iterator type" do
      result = tool.execute(node_type: "iterator")
      expect(result).to include("collection", "parallel", "max_parallel_branches", "loop", "done")
    end

    it "returns custom instructions for loop type" do
      result = tool.execute(node_type: "loop")
      expect(result).to include("condition", "max_iterations")
    end

    it "returns core instructions for http_request type" do
      result = tool.execute(node_type: "http_request")
      expect(result).to include("url", "method", "success", "error", "Runtime Branch Pruning")
      expect(result).to include("Use JSON Extract node after HTTP Request to parse JSON responses instead of Code")
    end

    it "includes advanced configuration fields for http_request type" do
      result = tool.execute(node_type: "http_request")
      expect(result).to include("auth_type", "body_mode")
    end

    it "returns custom instructions for code type" do
      result = tool.execute(node_type: "code")
      expect(result).to include("Last-resort node", "Sandbox", "var(")
      expect(result).to include("Do not use `code` for plain JSON parsing/extraction")
    end

    it "returns custom instructions for filter type" do
      result = tool.execute(node_type: "filter")
      expect(result).to include("collection", "match", "no_match", "Runtime Branch Pruning")
    end

    it "returns custom instructions for switch type" do
      result = tool.execute(node_type: "switch")
      expect(result).to include("expression", "cases", "Runtime Branch Pruning")
    end

    it "returns custom instructions for set_variable type" do
      result = tool.execute(node_type: "set_variable")
      expect(result).to include("assignments")
    end

    it "returns custom instructions for json_extract type" do
      result = tool.execute(node_type: "json_extract")
      expect(result).to include("source", "extractions", "json_extract_2", "data.items.0.title", "results.2.id")
      expect(result).to include("0.id")
      expect(result).to include("Prefer this over `code`")
      expect(result).to include("`{{node.variable}}`")
      expect(result).to include("A bare `node.variable` is literal text")
    end

    it "returns custom instructions for output type" do
      result = tool.execute(node_type: "output")
      expect(result).to include("selected_variables", "status", "status_code", "response_body", "Terminal node")
    end

    it "returns custom instructions for aggregate type" do
      result = tool.execute(node_type: "aggregate")
      expect(result).to include("collection", "operation", "sum", "does not count semantic matches")
    end

    it "returns auto-generated instructions for text_template type" do
      result = tool.execute(node_type: "text_template")
      expect(result).to include("Text Template", "Required Fields", "template",
                                "Configuration (data fields)", "Output Variables",)
    end

    it "returns auto-generated instructions for delay type" do
      result = tool.execute(node_type: "delay")
      expect(result).to include("Delay", "duration")
    end

    it "returns error for unknown type" do
      expect(tool.execute(node_type: "nonexistent")).to include("Unknown node type")
    end

    it "appends related resource lookup hints for llm type" do
      result = tool.execute(node_type: "llm")
      expect(result).to include("Related Resource Lookups")
      expect(result).to include("list_resources(kinds: ['llm_connectors', 'default_models', 'tools'])")
    end

    it "appends resource hints for generate_image type" do
      result = tool.execute(node_type: "generate_image")
      expect(result).to include("list_resources(kinds: ['llm_connectors', 'default_models'])")
    end

    it "appends resource hints for agent type" do
      result = tool.execute(node_type: "agent")
      expect(result).to include("list_resources(kinds: ['agents'])")
    end

    it "appends resource hints for mission type" do
      result = tool.execute(node_type: "mission")
      expect(result).to include("list_resources(kinds: ['missions'])")
    end

    it "omits the resource lookup section for types without hints" do
      expect(tool.execute(node_type: "code")).not_to include("Related Resource Lookups")
    end

    it "returns error message on unexpected failure" do
      allow(MissionNodePlugin).to receive(:resolve).and_raise(StandardError, "boom")
      result = tool.execute(node_type: "llm")
      expect(result).to include("Error getting node type info", "boom")
    end
  end
end
