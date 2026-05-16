# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::NodeConfigValidator do
  after(:each) { MissionNodePlugin.restore_defaults! } # rubocop:disable RSpec/HookArgument

  let(:malformed_input_fields_flow_data) do
    {
      "nodes" => [
        {
          "id" => "node-1",
          "type" => "input",
          "data" => {
            "fields" => [
              { "name" => "username", "type" => "string", "required" => true },
            ],
          },
        },
      ],
      "edges" => [],
    }
  end

  before do
    # Other specs may call MissionNodePlugin.reset! — ensure all built-in types are registered.
    unless MissionNodePlugin.type_map.key?("llm")
      MissionNodePlugin.register("input", "Missions::Nodes::Input",
                                 label: "Input", icon: "fa-solid fa-right-to-bracket",
                                 color: "#10b981", category: :input_output,)
      MissionNodePlugin.register("output", "Missions::Nodes::Output",
                                 label: "Output", icon: "fa-solid fa-arrow-right-from-bracket",
                                 color: "#ec4899", category: :input_output,)
      MissionNodePlugin.register("llm", "Missions::Nodes::Llm",
                                 label: "LLM", icon: "fa-solid fa-brain",
                                 color: "#6366f1", category: :node,)
      MissionNodePlugin.register("agent", "Missions::Nodes::Agent",
                                 label: "Agent", icon: "fa-solid fa-user-secret",
                                 color: "#4f46e5", category: :node,)
      MissionNodePlugin.register("mission", "Missions::Nodes::SubMission",
                                 label: "Mission", icon: "fa-solid fa-diagram-project",
                                 color: "#8b5cf6", category: :node,)
      MissionNodePlugin.register("condition", "Missions::Nodes::Condition",
                                 label: "Condition", icon: "fa-solid fa-code-branch",
                                 color: "#f97316", category: :control,)
      MissionNodePlugin.register("switch", "Missions::Nodes::Switch",
                                 label: "Switch", icon: "fa-solid fa-arrows-split-up-and-left",
                                 color: "#e11d48", category: :control,)
      MissionNodePlugin.register("iterator", "Missions::Nodes::Iterator",
                                 label: "Iterator", icon: "fa-solid fa-repeat",
                                 color: "#0ea5e9", category: :control,)
      MissionNodePlugin.register("loop", "Missions::Nodes::Loop",
                                 label: "Loop", icon: "fa-solid fa-arrows-rotate",
                                 color: "#14b8a6", category: :control,)
      MissionNodePlugin.register("set_variable", "Missions::Nodes::SetVariable",
                                 label: "Set Variable", icon: "fa-solid fa-equals",
                                 color: "#84cc16", category: :control,)
    end
  end

  describe "contract-backed validation" do
    before do
      stub_const("Missions::Nodes::ContractValidated", Class.new do
        include MissionNodePlugin

        class << self
          def node_type = "contract_validated"

          def field_contracts
            [
              field_contract(key: "prompt", kind: :template, value_type: :string, required: true),
              field_contract(key: "custom_llm_params", value_type: :string, json: true),
            ]
          end
        end
      end,)

      Missions::Nodes::ContractValidated.register_node!
    end

    it "uses field contracts for required and json validations" do
      invalid_json_error = Llm::ChatOptions::InvalidCustomParamsError.new("must be a JSON object")
      allow(Llm::ChatOptions).to receive(:normalize_custom_params).with("bad-json").and_raise(invalid_json_error)

      validator = described_class.new(
        node_type: "contract_validated",
        node_data: { "custom_llm_params" => "bad-json" },
      )

      expect(validator).not_to be_valid
      expect(validator.errors.attribute_names).to include(:prompt, :custom_llm_params)
      expect(validator.errors[:prompt]).to include("is required")
      expect(validator.errors[:custom_llm_params]).to include("must be a JSON object")
    end

    it "includes node-specific validation errors" do
      stub_const("Missions::Nodes::ConfigValidated", Class.new do
        include MissionNodePlugin

        class << self
          def node_type = "config_validated"
        end

        def validate_config!(_node_data = nil)
          raise ArgumentError, "config is invalid"
        end
      end,)

      Missions::Nodes::ConfigValidated.register_node!

      validator = described_class.new(node_type: "config_validated", node_data: {})

      expect(validator).not_to be_valid
      expect(validator.errors[:base]).to include("config is invalid")
    end
  end

  describe "flow check helpers" do
    it "handles nil flow data without errors" do
      errors = {}

      expect { described_class::FlowChecks.apply(nil, errors) }.not_to raise_error
      expect(errors).to eq({})
    end

    it "reads formula fields from node contracts" do
      pairs = described_class::FlowChecks.send(
        :formula_field_pairs,
        { "type" => "condition", "data" => { "expression" => "score > 0.5" } },
      )

      expect(pairs).to eq([["expression", "score > 0.5"]])
    end

    it "returns early when variable reference validation gets blank flow data" do
      errors = {}

      described_class::FlowChecks.send(:validate_variable_references, nil, errors)

      expect(errors).to eq({})
    end
  end

  describe ".validate_flow" do
    it "returns empty hash for a simple valid flow" do
      flow_data = {
        "nodes" => [
          { "id" => "node-1", "type" => "input", "data" => {} },
          { "id" => "node-2", "type" => "output", "data" => {} },
        ],
        "edges" => [],
      }

      expect(described_class.validate_flow(flow_data)).to eq({})
    end

    it "returns errors for nodes missing required config" do
      flow_data = {
        "nodes" => [
          { "id" => "node-1", "type" => "llm", "data" => { "llm_config_source" => "node" } },
          { "id" => "node-2", "type" => "condition", "data" => {} },
        ],
        "edges" => [],
      }

      errors = described_class.validate_flow(flow_data)

      expect(errors).to have_key("node-1")
      expect(errors).to have_key("node-2")
      expect(errors["node-1"].pluck(:field)).to contain_exactly("connector_id", "model")
      expect(errors["node-2"].pluck(:field)).to contain_exactly("expression")
    end

    it "does not include valid nodes in the result" do
      flow_data = {
        "nodes" => [
          { "id" => "node-1", "type" => "llm", "data" => { "connector_id" => "42", "model" => "gpt-4" } },
          { "id" => "node-2", "type" => "condition", "data" => {} },
        ],
        "edges" => [],
      }

      errors = described_class.validate_flow(flow_data)

      expect(errors).not_to have_key("node-1")
      expect(errors).to have_key("node-2")
    end

    it "returns empty hash for nil flow_data" do
      expect(described_class.validate_flow(nil)).to eq({})
    end

    it "returns empty hash for flow_data without nodes" do
      expect(described_class.validate_flow({ "edges" => [] })).to eq({})
    end

    it "flags duplicate input nodes" do
      flow_data = {
        "nodes" => [
          { "id" => "node-1", "type" => "input", "data" => {} },
          { "id" => "node-2", "type" => "input", "data" => {} },
        ],
        "edges" => [],
      }

      errors = described_class.validate_flow(flow_data)

      expect(errors).not_to have_key("node-1")
      expect(errors).to have_key("node-2")
      expect(errors["node-2"].first[:message]).to include("Only one input node")
    end

    it "flags malformed input fields that omit variable_name and field_type" do
      errors = described_class.validate_flow(malformed_input_fields_flow_data)

      expect(errors).to have_key("node-1")
      expect(errors["node-1"]).to include(
        include(field: "base", message: include("fields[0].variable_name is required")),
      )
      expect(errors["node-1"]).to include(
        include(field: "base", message: include("fields[0].field_type is required")),
      )
    end

    context "with variable reference validation" do
      let(:array_formula_flow_data) do
        {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "iterator",
              "data" => {
                "label" => "Iterate Numbers",
                "collection" => "[1, 2, 3]",
              },
            },
            {
              "id" => "node-2",
              "type" => "condition",
              "data" => {
                "expression" => "iterate_numbers.results == 2",
              },
            },
          ],
          "edges" => [
            { "id" => "edge-1", "source" => "node-1", "target" => "node-2", "sourceHandle" => "done" },
          ],
        }
      end

      let(:limit_formula_base_flow_data) do
        {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "input",
              "data" => {
                "fields" => [
                  { "variable_name" => "max_posts", "field_type" => "number", "required" => false },
                ],
              },
            },
            {
              "id" => "node-2",
              "type" => "limit",
              "data" => {
                "collection" => "[1,2,3]",
                "count" => nil,
              },
            },
          ],
          "edges" => [
            { "id" => "edge-1", "source" => "node-1", "target" => "node-2", "sourceHandle" => "default" },
          ],
        }
      end

      it "reports an error when a node references an unavailable variable" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "llm",
              "data" => {
                "connector_id" => "1",
                "model" => "gpt-4",
                "prompt" => "Hello {{missing_var}}!",
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors["node-1"]).to include(
          a_hash_including(field: "variables", message: /missing_var/),
        )
      end

      it "does not report an error when a node references a builtin variable" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "llm",
              "data" => {
                "connector_id" => "1",
                "model" => "gpt-4",
                "prompt" => "Process {{input}}",
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors).not_to have_key("node-1")
      end

      it "reports an error when a collection field references an unavailable variable" do
        flow_data = {
          "nodes" => [
            { "id" => "node-1", "type" => "input", "data" => {} },
            {
              "id" => "node-2",
              "type" => "iterator",
              "data" => {
                "collection" => "remove_duplicates.result",
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors["node-2"]).to include(
          a_hash_including(field: "collection", message: /remove_duplicates\.result/),
        )
      end

      it "does not report an error for a literal JSON array collection" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "iterator",
              "data" => {
                "collection" => "[1, 2, 3]",
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors).not_to have_key("node-1")
      end

      it "ignores non-string collection config values" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "iterator",
              "data" => {
                "collection" => [1, 2, 3],
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors).not_to have_key("node-1")
      end

      it "scans array values in unknown node types for variable references" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "unknown_future_type",
              "data" => { "options" => ["{{array_var}}", "static_text"] },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors["node-1"]).to include(
          a_hash_including(field: "variables", message: /array_var/),
        )
      end

      it "reports an error when a set_variable output shadows a blank global input" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "set_variable",
              "data" => {
                "assignments" => { "final_summary" => "'PASS'" },
              },
            },
          ],
          "edges" => [],
          "global_variables" => [
            { "key" => "final_summary", "value" => "", "type" => "string" },
          ],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors["node-1"]).to include(
          a_hash_including(field: "assignments", message: /blank global variable/i),
        )
      end

      it "reports an error when a formula uses an array output directly" do
        errors = described_class.validate_flow(array_formula_flow_data)

        expect(errors["node-2"]).to include(
          a_hash_including(field: "expression", message: /iterate_numbers\.results/),
        )
      end

      it "allows direct scalar outputs in formulas" do
        flow_data = array_formula_flow_data.deep_dup
        flow_data["nodes"][1]["data"]["expression"] = "iterate_numbers.total > 0"

        errors = described_class.validate_flow(flow_data)

        expect(errors).not_to have_key("node-2")
      end

      it "reports an error when a formula field uses {{...}} interpolation" do
        flow_data = limit_formula_base_flow_data.deep_dup
        flow_data["nodes"][1]["data"]["count"] = "{{max_posts}}"

        errors = described_class.validate_flow(flow_data)

        expect(errors["node-2"]).to include(
          a_hash_including(field: "count", message: /direct variable references, not \{\{\.\.\.\}\}/i),
        )
      end

      it "allows direct variable references in formula fields" do
        flow_data = limit_formula_base_flow_data.deep_dup
        flow_data["nodes"][1]["data"]["count"] = "max_posts"

        errors = described_class.validate_flow(flow_data)

        expect(errors).not_to have_key("node-2")
      end

      it "ignores non-string formula field values" do
        flow_data = limit_formula_base_flow_data.deep_dup
        flow_data["nodes"][1]["data"]["count"] = 3

        errors = described_class.validate_flow(flow_data)

        expect(errors).not_to have_key("node-2")
      end

      it "ignores blank set_variable assignments for formula-type checks" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "set_variable",
              "data" => {
                "assignments" => { "summary" => "" },
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors).to eq({})
      end

      it "ignores non-hash assignment payloads when scanning flow-level safeguards" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "set_variable",
              "data" => {
                "assignments" => 123,
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors).to eq({})
      end
    end
  end

  describe "per-type validations" do
    def validate_node(type, data = {})
      validator = described_class.new(node_type: type, node_data: data)
      validator.valid?
      validator.errors.map { |e| e.attribute.to_s }
    end

    context "with llm node" do
      it "defaults to system preference when connector_id and model are omitted" do
        expect(validate_node("llm")).to be_empty
      end

      it "requires connector_id and model for node configuration" do
        expect(validate_node("llm", { "llm_config_source" => "node" })).to contain_exactly("connector_id", "model")
      end

      it "passes with node configuration when connector_id and model are present" do
        data = { "llm_config_source" => "node", "connector_id" => "1", "model" => "gpt-4" }

        expect(validate_node("llm", data)).to be_empty
      end

      it "rejects invalid llm config sources" do
        expect(validate_node("llm", { "llm_config_source" => "tenant_magic" })).to contain_exactly("llm_config_source")
      end

      it "validates custom llm params json" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "llm",
              "data" => {
                "connector_id" => "1",
                "model" => "gpt-4",
                "custom_llm_params" => "not-json",
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors["node-1"]).to include(
          a_hash_including(field: "custom_llm_params", message: /valid JSON/),
        )
      end
    end

    context "with agent node" do
      it "requires agent_id" do
        expect(validate_node("agent")).to contain_exactly("agent_id")
      end

      it "passes when agent_id is present" do
        expect(validate_node("agent", { "agent_id" => "5" })).to be_empty
      end
    end

    context "with mission (sub_mission) node" do
      it "requires mission_id" do
        expect(validate_node("mission")).to contain_exactly("mission_id")
      end

      it "passes when mission_id is present" do
        expect(validate_node("mission", { "mission_id" => "10" })).to be_empty
      end
    end

    context "with condition node" do
      it "requires expression" do
        expect(validate_node("condition")).to contain_exactly("expression")
      end

      it "passes when expression is present" do
        expect(validate_node("condition", { "expression" => "x > 5" })).to be_empty
      end
    end

    context "with switch node" do
      it "requires expression" do
        expect(validate_node("switch")).to contain_exactly("expression")
      end

      it "passes when expression is present" do
        expect(validate_node("switch", { "expression" => "status" })).to be_empty
      end
    end

    context "with set_variable expression conventions" do
      def validate_set_variable_flow(assignments)
        described_class.validate_flow(
          {
            "nodes" => [
              {
                "id" => "node-1",
                "type" => "set_variable",
                "data" => { "assignments" => assignments },
              },
            ],
            "edges" => [],
          },
        )
      end

      it "allows CONCAT for string assembly" do
        expect(
          validate_node("set_variable", { "assignments" => { "summary" => "CONCAT('x=', STR(total))" } }),
        ).to be_empty
      end

      it "flags string concatenation with plus" do
        errors = validate_set_variable_flow({ "summary" => "'x=' + STR(total)" })

        expect(errors["node-1"]).to include(
          a_hash_including(
            field: "assignments",
            message: /use CONCAT/i,
          ),
        )
      end

      it "flags string concatenation with STR in stringified assignments" do
        errors = validate_set_variable_flow('{"summary":"total + STR(other)"}')

        expect(errors["node-1"]).to include(
          a_hash_including(
            field: "assignments",
            message: /use CONCAT/i,
          ),
        )
      end

      it "flags formula-like assignments that use {{...}} interpolation" do
        errors = validate_set_variable_flow(
          {
            "effective_max_posts" => "IF({{max_posts}} > 0, {{max_posts}}, 8)",
          },
        )

        expect(errors["node-1"]).to include(
          a_hash_including(
            field: "assignments.effective_max_posts",
            message: /direct variable references, not \{\{\.\.\.\}\}/i,
          ),
        )
      end

      it "ignores invalid assignment json when checking conventions" do
        expect(validate_set_variable_flow("{")).to eq({})
      end

      it "ignores non-string assignment expressions when checking conventions" do
        expect(validate_set_variable_flow({ "count" => 1 })).to eq({})
      end
    end

    context "with iterator node" do
      it "requires collection" do
        expect(validate_node("iterator")).to contain_exactly("collection")
      end

      it "passes when collection is present" do
        expect(validate_node("iterator", { "collection" => "items" })).to be_empty
      end
    end

    context "with json_extract node" do
      it "rejects a bare plain string source" do
        flow_data = {
          "nodes" => [
            {
              "id" => "node-1",
              "type" => "json_extract",
              "data" => {
                "source" => "node.variable",
              },
            },
          ],
          "edges" => [],
        }

        errors = described_class.validate_flow(flow_data)

        expect(errors["node-1"]).to include(
          a_hash_including(
            field: "base",
            message: /source must be valid JSON or a \{\{variable\}\} template reference/i,
          ),
        )
      end

      it "allows literal JSON and template variable sources" do
        expect(validate_node("json_extract", { "source" => '{"name":"Alice"}' })).to be_empty
        expect(validate_node("json_extract", { "source" => "{{node.variable}}" })).to be_empty
      end
    end

    context "with set_variable required fields" do
      it "requires assignments" do
        expect(validate_node("set_variable")).to contain_exactly("assignments")
      end

      it "fails when assignments is empty hash" do
        expect(validate_node("set_variable", { "assignments" => {} })).to contain_exactly("assignments")
      end

      it "passes when assignments has entries" do
        expect(validate_node("set_variable", { "assignments" => { "x" => "1" } })).to be_empty
      end
    end

    context "with nodes that have no required fields" do
      ["input", "output", "loop"].each do |type|
        it "#{type} has no required fields" do
          expect(validate_node(type)).to be_empty
        end
      end
    end

    context "with nil node_data" do
      it "treats llm nodes as system preference when data is missing" do
        validator = described_class.new(node_type: "llm", node_data: nil)
        validator.valid?
        expect(validator.errors).to be_empty
      end

      it "handles set_variable nodes with nil data" do
        validator = described_class.new(node_type: "set_variable", node_data: nil)
        validator.valid?

        expect(validator.errors.map { |e| e.attribute.to_s }).to contain_exactly("assignments")
      end
    end

    context "with unknown node type" do
      it "returns no errors" do
        expect(validate_node("nonexistent_type")).to be_empty
      end
    end
  end
end
