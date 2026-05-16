# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Code do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns code" do
      expect(described_class.node_type).to eq("code")
    end
  end

  describe ".node_category" do
    it "is node" do
      expect(described_class.node_category).to eq(:node)
    end
  end

  describe ".required_field_keys" do
    it "requires code" do
      expect(described_class.required_field_keys).to eq(["code"])
    end
  end

  describe ".variable_schema" do
    it "declares result output" do
      schema = described_class.variable_schema
      expect(schema.outputs.map(&:name)).to include("result")
    end

    it "declares wildcard for dynamic output variables" do
      schema = described_class.variable_schema
      expect(schema.outputs.map(&:name)).to include("*")
    end
  end

  describe ".extract_variables" do
    it "extracts configured output variables" do
      data = { "output_variables" => [{ "name" => "count", "description" => "Item count" }] }
      variables = []
      seen = Set.new

      described_class.extract_variables(data, "Code Node", variables, seen)

      expect(variables.size).to eq(1)
      expect(variables.first[:key]).to eq("count")
      expect(variables.first[:description]).to eq("Item count")
    end

    it "skips variables with blank names" do
      data = { "output_variables" => [{ "name" => "", "description" => "Empty" }] }
      variables = []
      seen = Set.new

      described_class.extract_variables(data, "Code Node", variables, seen)

      expect(variables).to be_empty
    end

    it "handles missing output_variables" do
      data = {}
      variables = []
      seen = Set.new

      described_class.extract_variables(data, "Code Node", variables, seen)

      expect(variables).to be_empty
    end

    it "handles string JSON output_variables" do
      data = { "output_variables" => '[{"name": "total", "description": "Sum"}]' }
      variables = []
      seen = Set.new

      described_class.extract_variables(data, "Code Node", variables, seen)

      expect(variables.size).to eq(1)
      expect(variables.first[:key]).to eq("total")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "executes simple Ruby code" do
      context.set_variable("_current_node_data", { "code" => "2 + 3" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(5)
    end

    it "can access upstream variables via var()" do
      context.set_variable("name", "Alice")
      context.set_variable("_current_node_data", { "code" => "var('name').upcase" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("ALICE")
    end

    it "does not expose internal underscore-prefixed variables in the sandbox" do
      context.set_variable("name", "Alice")
      context.set_variable("_secret", "hidden")
      context.set_variable("_current_node_data", { "code" => "[var('name'), var('_secret')]" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(["Alice", nil])
    end

    it "falls back to normalized variable names when a direct lookup misses" do
      context.set_variable("full_name", "Alice")
      context.set_variable("_current_node_data", { "code" => "var('Full Name').upcase" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("ALICE")
    end

    it "can access node-scoped upstream variables via dot syntax" do
      context.set_node_variables("Writer", { "response" => "Draft" })
      context.set_variable("_current_node_data", { "code" => "var('writer.response').upcase" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("DRAFT")
    end

    it "normalizes qualified node-scoped lookups when the direct key misses" do
      context.set_node_variables("Writer", { "Response Text" => "Draft" })
      context.set_variable("_current_node_data", { "code" => "var('Writer.Response Text').upcase" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("DRAFT")
    end

    it "fails with no code" do
      context.set_variable("_current_node_data", { "code" => "" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("No code provided")
    end

    it "rejects unsafe code with File access" do
      context.set_variable("_current_node_data", { "code" => "File.read('/etc/passwd')" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("prohibited")
    end

    it "rejects unsafe code with system calls" do
      context.set_variable("_current_node_data", { "code" => "system('ls')" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("prohibited")
    end

    it "rejects eval calls" do
      context.set_variable("_current_node_data", { "code" => "eval('1+1')" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("prohibited")
    end

    it "rejects backtick execution" do
      context.set_variable("_current_node_data", { "code" => "`ls`" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("prohibited")
    end

    it "handles runtime errors gracefully" do
      context.set_variable("_current_node_data", { "code" => "raise 'test error'" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("test error")
    end

    it "can work with arrays" do
      context.set_variable("_current_node_data", { "code" => "[1, 2, 3].map { |x| x * 2 }" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq([2, 4, 6])
    end

    it "can work with hashes" do
      context.set_variable("_current_node_data", { "code" => "{ name: 'Alice', age: 30 }" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq({ name: "Alice", age: 30 })
    end

    it "can set output variables via set()" do
      context.set_variable("_current_node_data", { "code" => "set('output', 'hello'); var('output')" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("hello")
      expect(result.variables["output"]).to eq("hello")
    end

    it "propagates multiple set() variables alongside result" do
      code = <<~RUBY
        set('count', 3)
        set('label', 'test')
        'done'
      RUBY
      context.set_variable("_current_node_data", { "code" => code })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("done")
      expect(result.variables["count"]).to eq(3)
      expect(result.variables["label"]).to eq("test")
    end

    it "rejects const_get escape attempts" do
      context.set_variable("_current_node_data", { "code" => "self.class.const_get(:File)" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("prohibited")
    end

    it "rejects binding escape attempts" do
      context.set_variable("_current_node_data", { "code" => "binding.eval('1')" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("prohibited")
    end
  end
end
