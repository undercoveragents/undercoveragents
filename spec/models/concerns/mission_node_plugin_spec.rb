# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionNodePlugin do
  # Restore the full built-in registry after any test that mutates it.
  after(:each) { described_class.restore_defaults! } # rubocop:disable RSpec/HookArgument

  describe ".type_keys" do
    it "returns an array of all registered type keys" do
      described_class.reset!
      described_class.register("alpha", "AlphaClass", label: "Alpha", icon: "x", color: "#fff", category: :node)
      described_class.register("beta", "BetaClass", label: "Beta", icon: "x", color: "#fff", category: :node)
      expect(described_class.type_keys).to eq(["alpha", "beta"])
    end
  end

  describe ".type_map" do
    it "returns a copy of the type map with all registered keys" do
      map = described_class.type_map
      expect(map).to be_a(Hash)
      expect(map).to include("input" => "Missions::Nodes::Input")
    end
  end

  describe ".label_for / .icon_for / .color_for / .category_for / .metadata_for" do
    it "returns metadata values for a registered key" do
      expect(described_class.label_for("input")).to eq("Input")
      expect(described_class.icon_for("input")).to eq("fa-solid fa-right-to-bracket")
      expect(described_class.color_for("input")).to eq("#10b981")
      expect(described_class.category_for("input")).to eq("input_output")
      expect(described_class.metadata_for("input")).to be_a(Hash)
    end

    it "returns nil for unknown keys" do
      expect(described_class.label_for("nonexistent")).to be_nil
      expect(described_class.icon_for("nonexistent")).to be_nil
      expect(described_class.color_for("nonexistent")).to be_nil
      expect(described_class.category_for("nonexistent")).to be_nil
      expect(described_class.metadata_for("nonexistent")).to be_nil
    end
  end

  describe ".register duplicate" do
    it "silently returns when re-registering the same class name" do
      expect do
        described_class.register("input", "Missions::Nodes::Input",
                                 label: "Input", icon: "fa-solid fa-right-to-bracket",
                                 color: "#10b981", category: :input_output,)
      end.not_to raise_error
    end

    it "raises ArgumentError when re-registering the same key with a different class" do
      expect do
        described_class.register("input", "Missions::Nodes::SomethingElse",
                                 label: "Input", icon: "fa-solid fa-right-to-bracket",
                                 color: "#10b981", category: :input_output,)
      end.to raise_error(ArgumentError, /already registered/)
    end
  end

  describe "default class method implementations" do
    # Build a class that includes MissionNodePlugin without overriding any defaults.
    let(:node_class) do
      stub_const("TestDefaultNode", Class.new do
        include MissionNodePlugin

        def self.name
          "Missions::Nodes::TestDefault"
        end
      end,)
      TestDefaultNode
    end

    it "derives node_type from the demodulized underscored class name" do
      expect(node_class.node_type).to eq("test_default")
    end

    it "derives node_label from the demodulized titleized class name" do
      expect(node_class.node_label).to eq("Test Default")
    end

    it "provides a default node_icon" do
      expect(node_class.node_icon).to eq("fa-solid fa-circle")
    end

    it "provides a default node_color" do
      expect(node_class.node_color).to eq("#6366f1")
    end

    it "provides a default node_category" do
      expect(node_class.node_category).to eq(:node)
    end

    it "provides a default node_description (empty string)" do
      expect(node_class.node_description).to eq("")
    end

    it "provides a default output_ports implementation" do
      instance = node_class.new
      expect(instance.output_ports).to eq([{ key: "default", label: "Output" }])
    end

    it "provides a default variable_schema (empty)" do
      schema = node_class.variable_schema
      expect(schema).to be_a(Missions::VariableSchema)
      expect(schema.inputs).to be_empty
      expect(schema.outputs).to be_empty
    end

    it "provides default empty field_contracts" do
      expect(node_class.field_contracts).to eq([])
    end

    it "provides a default empty input_schema" do
      expect(node_class.input_schema).to eq([])
    end

    it "provides a default validate_config! that is a no-op" do
      instance = node_class.new
      expect { instance.validate_config! }.not_to raise_error
    end

    it "provides a default execute that raises NotImplementedError" do
      instance = node_class.new
      ctx = instance_double(Missions::ExecutionContext)
      expect { instance.execute(ctx) }.to raise_error(NotImplementedError)
    end

    it "provides a default singleton? returning false" do
      expect(node_class.singleton?).to be(false)
    end

    it "provides a default extract_variables that is a no-op" do
      variables = []
      seen = Set.new
      expect { node_class.extract_variables({}, "Test", variables, seen) }.not_to raise_error
      expect(variables).to be_empty
    end

    it "provides default empty dynamic_output_variables" do
      expect(node_class.dynamic_output_variables({})).to eq([])
    end
  end

  describe ".register_from_class" do
    it "registers a node class from its metadata methods" do
      described_class.reset!

      klass = Missions::Nodes::Llm
      described_class.register_from_class(klass)

      expect(described_class.label_for("llm")).to eq("Generate Text")
      expect(described_class.icon_for("llm")).to eq("fa-solid fa-brain")
      expect(described_class.color_for("llm")).to eq("#6366f1")
    end

    it "falls back to empty field contracts when a class does not define them" do
      described_class.reset!

      klass = Class.new do
        def self.name = "Missions::Nodes::BareMetadata"
        def self.node_type = "bare_metadata"
        def self.node_label = "Bare"
        def self.node_icon = "fa-solid fa-circle"
        def self.node_color = "#000000"
        def self.node_category = :node
        def self.node_description = "Bare metadata"
        def self.default_output_ports = [{ key: "default", label: "Output" }]
      end

      described_class.register_from_class(klass)

      expect(described_class.metadata_for("bare_metadata")[:field_contracts]).to eq([])
    end
  end

  describe "field contract helpers" do
    let(:configured_node_class) do
      stub_const("ConfiguredContractNode", Class.new do
        include MissionNodePlugin

        def self.name
          "Missions::Nodes::ConfiguredContract"
        end

        def self.field_contracts
          [
            field_contract(key: "prompt", kind: :template, value_type: :string, description: "Prompt", required: true),
            field_contract(key: "options", value_type: :string, description: "Options", json: true),
            field_contract(
              key: "connector_id",
              kind: :id_ref,
              value_type: :string,
              description: "Connector",
              required: true,
            ),
            field_contract(key: "metadata", value_type: :hash, description: "Metadata", json: true),
          ]
        end
      end,)
      ConfiguredContractNode
    end

    let(:contract_node_class) do
      stub_const("ContractExtractionNode", Class.new do
        include MissionNodePlugin

        def self.name
          "Missions::Nodes::ContractExtraction"
        end

        def self.field_contracts
          [
            field_contract(key: "prompt", kind: :template, value_type: :string),
            field_contract(key: "expression", kind: :formula, value_type: :string),
            field_contract(key: "collection", kind: :collection_ref, value_type: :array),
            field_contract(key: "assignments", kind: :assignment_map, value_type: :hash),
            field_contract(key: "fields", kind: :input_fields, value_type: :array),
          ]
        end
      end,)
      ContractExtractionNode
    end

    it "derives required and json field keys from explicit field contracts", :aggregate_failures do
      contracts = configured_node_class.field_contracts.index_by(&:key)

      expect(contracts.keys).to contain_exactly("prompt", "options", "connector_id", "metadata")
      expect(contracts["prompt"]).to be_required
      expect(contracts["prompt"].value_type).to eq(:string)
      expect(contracts["connector_id"].kind).to eq(:id_ref)
      expect(contracts["connector_id"].value_type).to eq(:string)
      expect(contracts["options"]).to be_json
      expect(contracts["metadata"]).to be_json
      expect(configured_node_class.required_field_keys).to eq(["prompt", "connector_id"])
      expect(configured_node_class.json_field_keys).to eq(["options", "metadata"])
    end

    it "extracts helper variables from field contracts", :aggregate_failures do
      variables = []
      seen = Set.new

      contract_node_class.extract_variables(
        {
          "prompt" => "Hello {{user}}",
          "expression" => "{{score}} > 0.8",
          "collection" => "items",
          "assignments" => { "greeting" => "Hi {{name}}" },
          "fields" => [{ "variable_name" => "query", "field_type" => "string", "required" => true }],
        },
        "Contract",
        variables,
        seen,
      )

      expect(variables.pluck(:key)).to include("user", "score", "items", "name", "query")
      expect(seen).to include("greeting")
    end

    it "delegates extract_variables_from_field_contracts through the node class" do
      variables = []
      seen = Set.new

      contract_node_class.extract_variables_from_field_contracts(
        { "prompt" => "Hello {{user}}" },
        "Contract",
        variables,
        seen,
      )

      expect(variables.pluck(:key)).to include("user")
    end

    it "handles nested template values, blank input fields, and non-string collections", :aggregate_failures do
      variables = []
      seen = Set.new

      contract_node_class.extract_variables(
        {
          "prompt" => { "intro" => "Hello {{user}}", "items" => ["{{topic}}"] },
          "expression" => "",
          "collection" => 123,
          "assignments" => { "greeting" => ["Hi {{name}}"] },
          "fields" => [{ "variable_name" => "" }, { "variable_name" => "query" }],
        },
        "Contract",
        variables,
        seen,
      )

      expect(variables.pluck(:key)).to include("user", "topic", "name", "query")
      expect(variables.pluck(:key)).not_to include(123)
    end

    it "collects validation-time references from field contracts" do
      refs = contract_node_class.reference_names_from_field_contracts(
        {
          "prompt" => "Hello {{user}}",
          "expression" => "{{score}} > 0.8",
          "assignments" => { "greeting" => "Hi {{name}}" },
        },
      )

      expect(refs).to eq(Set["user", "score", "name"])
    end

    it "collects nested hash and array references from field contracts" do
      refs = contract_node_class.reference_names_from_field_contracts(
        {
          "prompt" => { "intro" => "Hello {{user}}", "items" => ["{{topic}}"] },
          "assignments" => { "greeting" => ["Hi {{name}}"] },
        },
      )

      expect(refs).to eq(Set["user", "topic", "name"])
    end

    it "ignores non-hash assignment JSON payloads" do
      variables = []
      seen = Set.new

      contract_node_class.extract_variables(
        { "assignments" => "[]" },
        "Contract",
        variables,
        seen,
      )

      expect(variables).to be_empty
    end

    it "ignores non-array and malformed input field payloads" do
      variables = []
      seen = Set.new

      contract_node_class.extract_variables(
        { "fields" => '{"variable_name":"query"}' },
        "Contract",
        variables,
        seen,
      )
      contract_node_class.extract_variables(
        { "fields" => "{bad-json}" },
        "Contract",
        variables,
        seen,
      )

      expect(variables).to be_empty
    end

    it "extracts direct collection variables only for identifier-like collection refs" do
      variables = []
      seen = Set.new

      described_class.extract_collection_var(variables, seen, { "collection" => "items" }, "Contract")
      described_class.extract_collection_var(variables, seen, { "collection" => nil }, "Contract")

      expect(variables.pluck(:key)).to include("items")
    end

    it "ignores non-identifier collection refs" do
      variables = []
      seen = Set.new

      described_class.extract_collection_var(variables, seen, { "collection" => "[1,2,3]" }, "Contract")

      expect(variables).to be_empty
    end
  end

  describe ".ensure_class_loaded!" do
    it "skips constantization when output port metadata is already cached" do
      described_class.reset!
      described_class.instance_variable_set(:@type_map, { "known" => Object.new })
      described_class.instance_variable_set(:@metadata_map, { "known" => { output_ports: [{ key: "default" }] } })

      expect { described_class.send(:ensure_class_loaded!, "known") }.not_to raise_error
    end
  end

  describe ".register with singleton" do
    it "stores singleton flag in metadata" do
      described_class.reset!
      described_class.register("test", "TestClass", label: "Test", icon: "x", color: "#fff",
                                                    category: :node, singleton: true,)

      meta = described_class.metadata_for("test")
      expect(meta[:singleton]).to be(true)
    end

    it "defaults singleton to false" do
      described_class.reset!
      described_class.register("test", "TestClass", label: "Test", icon: "x", color: "#fff", category: :node)

      meta = described_class.metadata_for("test")
      expect(meta[:singleton]).to be(false)
    end
  end

  describe "singleton node detection" do
    it "marks input as singleton via register_defaults!" do
      meta = described_class.metadata_for("input")
      expect(meta[:singleton]).to be(true)
    end

    it "marks non-singleton nodes as false" do
      meta = described_class.metadata_for("llm")
      expect(meta[:singleton]).to be(false)
    end
  end

  describe ".add_variable" do
    it "adds a variable to the list" do
      variables = []
      seen = Set.new

      described_class.add_variable(variables, seen, "name", "template", "LLM", "A variable")

      expect(variables.size).to eq(1)
      expect(variables.first[:key]).to eq("name")
    end

    it "skips blank keys" do
      variables = []
      seen = Set.new

      described_class.add_variable(variables, seen, "", "template", "LLM", "A variable")
      described_class.add_variable(variables, seen, nil, "template", "LLM", "A variable")

      expect(variables).to be_empty
    end

    it "deduplicates by key" do
      variables = []
      seen = Set.new

      described_class.add_variable(variables, seen, "name", "template", "N1", "First")
      described_class.add_variable(variables, seen, "name", "template", "N2", "Second")

      expect(variables.size).to eq(1)
    end
  end

  describe ".extract_template_vars" do
    it "extracts {{variable}} references from templates" do
      variables = []
      seen = Set.new

      described_class.extract_template_vars(variables, seen, "Hello {{user}}, {{topic}}", "LLM", "LLM")

      expect(variables.pluck(:key)).to contain_exactly("user", "topic")
    end

    it "skips internal variables" do
      variables = []
      seen = Set.new

      described_class.extract_template_vars(variables, seen, "{{_current_node_data}}", "LLM", "LLM")

      expect(variables).to be_empty
    end

    it "skips internal variables like _current_node_data" do
      variables = []
      seen = Set.new

      described_class.extract_template_vars(variables, seen, "{{user}} and {{_current_node_data}}", "LLM", "LLM")

      keys = variables.pluck(:key)
      expect(keys).to include("user")
      expect(keys).not_to include("_current_node_data")
    end
  end

  describe ".extract_expression_vars" do
    it "extracts identifier tokens from expressions" do
      variables = []
      seen = Set.new

      described_class.extract_expression_vars(variables, seen, "score > threshold", "Check")

      expect(variables.pluck(:key)).to contain_exactly("score", "threshold")
    end

    it "skips reserved words" do
      variables = []
      seen = Set.new

      described_class.extract_expression_vars(variables, seen, "true and false or nil", "Check")

      expect(variables).to be_empty
    end

    it "skips internal variables in expression templates" do
      variables = []
      seen = Set.new

      described_class.extract_expression_vars(variables, seen, "{{user}} + {{_current_node_data}}", "Condition")

      keys = variables.pluck(:key)
      expect(keys).to include("user")
      expect(keys).not_to include("_current_node_data")
    end

    it "returns early for blank expressions" do
      variables = []
      seen = Set.new

      described_class.extract_expression_vars(variables, seen, "", "Condition")

      expect(variables).to be_empty
    end
  end

  describe "designer_instructions" do
    it "includes singleton info for singleton nodes" do
      result = Missions::Nodes::Input.designer_instructions
      expect(result).to include("Singleton")
    end

    it "includes required fields section when present" do
      result = Missions::Nodes::Llm.designer_instructions
      expect(result).to include("connector_id")
      expect(result).to include("model")
    end

    it "documents reasoning guidance for llm nodes" do
      result = Missions::Nodes::Llm.designer_instructions

      expect(result).to include("deeper reasoning")
      expect(result).to include("simple rewrite")
      expect(result).to include("thinking_budget")
      expect(result).to include("tool_ids")
    end

    it "includes input schema section when present" do
      result = Missions::Nodes::TextTemplate.designer_instructions
      expect(result).to include("Configuration (data fields)")
      expect(result).to include("template")
    end

    it "includes output variables with port info" do
      # Use a stub class since no built-in non-overriding node has ported outputs
      stub_class = Class.new do
        include MissionNodePlugin

        class << self
          def node_type = "stub"
          def node_label = "Stub"
          def node_icon = "fa-solid fa-cog"
          def node_color = "#000"
          def node_category = :node
          def node_description = "Stub node"

          def variable_schema
            Missions::VariableSchema.new(
              outputs: [{ name: "result", type: :string, description: "Result", port: "done" }],
            )
          end
        end
      end

      result = stub_class.designer_instructions
      expect(result).to include("Output Variables")
      expect(result).to include("[port: done]")
    end

    it "includes output ports section" do
      result = Missions::Nodes::Condition.designer_instructions
      expect(result).to include("Output Ports")
      expect(result).to include("`true`")
    end

    it "omits output variables section when schema has no outputs" do
      stub_class = Class.new do
        include MissionNodePlugin

        class << self
          def node_type = "no_out"
          def node_label = "NoOut"
          def node_icon = "fa-solid fa-cog"
          def node_color = "#000"
          def node_category = :node
          def node_description = "Node without outputs"
          def variable_schema = Missions::VariableSchema.new(outputs: [])
          def default_output_ports = []
        end
      end

      result = stub_class.designer_instructions
      expect(result).not_to include("Output Variables")
      expect(result).not_to include("Output Ports")
    end

    it "includes singleton info via base method" do
      stub_class = Class.new do
        include MissionNodePlugin

        class << self
          def node_type = "single"
          def node_label = "Single"
          def node_icon = "fa-solid fa-cog"
          def node_color = "#000"
          def node_category = :node
          def node_description = "Singleton stub"
          def singleton? = true
        end
      end

      result = stub_class.designer_instructions
      expect(result).to include("Singleton")
    end
  end
end
