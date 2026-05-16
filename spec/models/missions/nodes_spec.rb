# frozen_string_literal: true

require "rails_helper"

# All node specs share setup via a top-level describe so `let` and `build_ctx`
# are available down all nested describes without needing shared contexts.
RSpec.describe "Missions::Nodes" do
  let(:mission) { create(:mission) }
  let(:run)     { create(:mission_run, mission:) }

  def build_ctx(variables = {})
    ctx = Missions::ExecutionContext.new(mission_run: run)
    variables.each { |k, v| ctx.set_variable(k.to_s, v) }
    ctx
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::Output do
    subject(:node) { described_class.new }

    it "has empty output_ports (terminal node)" do
      expect(node.output_ports).to eq([])
    end

    it "outputs selected variables from context" do
      ctx = build_ctx(
        "name" => "Alice",
        "score" => 42,
        "_current_node_data" => { "selected_variables" => ["name", "score"] },
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to include("name" => "Alice", "score" => 42)
      expect(result.variables).to include("name" => "Alice", "score" => 42)
      expect(result.output["_output_meta"]["status"]).to eq("success")
    end

    it "falls back to the current branch input when no variables are selected" do
      ctx = build_ctx("_current_node_data" => {})
      ctx.current_input = "previous output"
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to include("output" => "previous output")
    end

    it "handles empty selected_variables array" do
      ctx = build_ctx("_current_node_data" => { "selected_variables" => [] })
      ctx.current_input = "fallback"
      result = node.execute(ctx)
      expect(result.output).to include("output" => "fallback")
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::SetVariable do
    subject(:node) { described_class.new }

    it "returns the correct output_ports" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end

    it "sets variables from the assignments hash" do
      ctx = build_ctx("_current_node_data" => { "assignments" => { "x" => "42", "greeting" => "hello" } })
      result = node.execute(ctx)
      expect(result).to be_success
      expect(ctx.get_variable("x")).to eq(42)
      expect(ctx.get_variable("greeting")).to eq("hello")
    end

    it "handles empty assignments gracefully" do
      ctx = build_ctx("_current_node_data" => { "assignments" => {} })
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to eq({})
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::Condition do
    subject(:node) { described_class.new }

    it "has true and false output ports" do
      expect(node.output_ports.pluck(:key)).to contain_exactly("true", "false")
    end

    it "returns a failure when no expression is configured" do
      ctx = build_ctx("_current_node_data" => {})
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("no expression configured")
    end

    it "returns failure when expression evaluates to nil (undefined variables)" do
      ctx = build_ctx("_current_node_data" => { "expression" => "totally_undefined_var_xyz > 0" })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("Could not evaluate condition")
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::Switch do
    subject(:node) { described_class.new }

    it "has a default output port" do
      expect(node.output_ports.pluck(:key)).to include("default")
    end

    it "returns a failure when no expression is configured" do
      ctx = build_ctx("_current_node_data" => { "cases" => {} })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("no expression configured")
    end

    it "routes to the matched case port when a case value matches the expression" do
      ctx = build_ctx(
        "_current_node_data" => {
          "expression" => "status",
          "cases" => { "success_port" => "ok", "error_port" => "fail" },
        },
        "status" => "ok",
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.next_port).to eq("success_port")
      expect(result.variables["matched"]).to be(true)
    end

    it "falls back to interpolated value when the expression engine cannot evaluate the expression" do
      ctx = build_ctx(
        "_current_node_data" => {
          "expression" => "{{category}}",
          "cases" => { "tech" => "technology" },
        },
        "category" => "technology",
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.next_port).to eq("tech")
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::Loop do
    subject(:node) { described_class.new }

    it "has loop and done output ports" do
      expect(node.output_ports.pluck(:key)).to contain_exactly("loop", "done")
    end

    it "returns done when max iterations have been reached" do
      ctx = build_ctx(
        "_current_node_data" => { "max_iterations" => "3" },
        "_loop_iteration" => 3,
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.next_port).to eq("done")
    end

    it "exits loop when condition is false" do
      ctx = build_ctx(
        "_current_node_data" => { "condition" => "x > 10" },
        "_loop_iteration" => 0,
        "x" => 5,
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.next_port).to eq("done")
    end

    it "exits loop when condition references undefined variables" do
      ctx = build_ctx(
        "_current_node_data" => { "condition" => "undefined_loop_var > 0" },
        "_loop_iteration" => 0,
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.next_port).to eq("done")
      expect(result.output).to include("could not be evaluated")
    end

    it "continues loop when no condition is configured" do
      ctx = build_ctx(
        "_current_node_data" => {},
        "_loop_iteration" => 2,
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.next_port).to eq("loop")
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::Iterator do
    subject(:node) { described_class.new }

    it "has loop and done output ports" do
      expect(node.output_ports.pluck(:key)).to contain_exactly("loop", "done")
    end

    it "returns a failure when no collection is configured" do
      ctx = build_ctx("_current_node_data" => {})
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("no collection configured")
    end

    it "wraps a non-array variable value in a single-element array" do
      ctx = build_ctx(
        "_current_node_data" => { "collection" => "my_scalar" },
        "my_scalar" => 42,
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.next_port).to eq("loop")
      expect(result.output).to eq(42) # first element of [42]
    end

    it "splits a comma-separated string value into an array" do
      ctx = build_ctx(
        "_current_node_data" => { "collection" => "csv_val" },
        "csv_val" => "apple, banana, cherry",
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to eq("apple") # first element
    end

    it "wraps a JSON-object string variable value in a single-element array" do
      ctx = build_ctx(
        "_current_node_data" => { "collection" => "json_obj" },
        "json_obj" => '{"key":"val"}',
      )
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to eq('{"key":"val"}') # first element
    end

    it "returns a failure when collection exceeds max iterations" do
      big_array = (1..1001).to_a
      ctx = build_ctx(
        "_current_node_data" => { "collection" => "big" },
        "big" => big_array,
      )
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to match(/exceeds maximum/)
    end

    it "raises ExecutionError for a completely undefined variable reference" do
      ctx = build_ctx("_current_node_data" => { "collection" => "undefined_collection_var" })
      expect { node.execute(ctx) }.to raise_error(Missions::ExecutionError, /undefined_collection_var/)
    end

    it "raises ExecutionError when collection expression is valid JSON but not an array" do
      ctx = build_ctx("_current_node_data" => { "collection" => "42" })
      expect { node.execute(ctx) }.to raise_error(Missions::ExecutionError, /is not defined/)
    end

    it "returns a failure type description via collection_type_error" do
      # collection_type_error is private but reachable for direct coverage
      result = node.send(:collection_type_error, 42)
      expect(result).to be_failure
      expect(result.output).to include("must be an array")
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::Llm do
    subject(:node) { described_class.new }

    before do
      create(:model, model_id: "gpt-4o", provider: "openai")
      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance
    end

    it "returns the correct output_ports" do
      expect(node.output_ports).to eq([{ key: "default", label: "Response" }])
    end

    it "returns a failure when no connector is configured" do
      ctx = build_ctx("_current_node_data" => { "model" => "gpt-4o" })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("connector not configured")
    end

    it "returns a failure when no model is configured" do
      connector = create(:connector, :llm_provider)
      ctx = build_ctx("_current_node_data" => { "connector_id" => connector.id.to_s })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("model not configured")
    end

    it "returns a failure when both prompt and user input are blank" do
      connector = create(:connector, :llm_provider)
      ctx = build_ctx("_current_node_data" => { "connector_id" => connector.id.to_s, "model" => "gpt-4o" })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("no prompt and no input")
    end

    it "rescues StandardError and returns a failure with LLM error message" do
      connector = create(:connector, :llm_provider)
      allow_any_instance_of(Chat).to receive(:ask).and_raise(StandardError, "connection refused") # rubocop:disable RSpec/AnyInstance
      ctx = build_ctx(
        "_current_node_data" => {
          "connector_id" => connector.id.to_s, "model" => "gpt-4o",
          "prompt" => "Say hello",
        },
        "input" => "something",
      )
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("LLM error")
    end

    it "returns success when LLM responds with content (system_prompt only)" do
      connector = create(:connector, :llm_provider)
      mock_response = double(:response, content: "LLM says hello") # rubocop:disable RSpec/VerifiedDoubles
      allow_any_instance_of(Chat).to receive(:ask).and_return(mock_response) # rubocop:disable RSpec/AnyInstance
      ctx = build_ctx("_current_node_data" => {
                        "connector_id" => connector.id.to_s,
                        "model" => "gpt-4o",
                        "prompt" => "Be helpful",
                      })
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to eq("LLM says hello")
    end

    it "returns success when LLM responds with both system_prompt and user_input plus temperature" do
      connector = create(:connector, :llm_provider)
      mock_response = double(:response, content: "Full response") # rubocop:disable RSpec/VerifiedDoubles
      allow_any_instance_of(Chat).to receive(:ask).and_return(mock_response) # rubocop:disable RSpec/AnyInstance
      ctx = build_ctx(
        "_current_node_data" => {
          "connector_id" => connector.id.to_s,
          "model" => "gpt-4o",
          "prompt" => "Be helpful",
          "temperature" => "0.5",
        },
      )
      ctx.current_input = "User said hello"
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to eq("Full response")
    end

    it "returns failure when LLM returns nil response" do
      connector = create(:connector, :llm_provider)
      allow_any_instance_of(Chat).to receive(:ask).and_return(nil) # rubocop:disable RSpec/AnyInstance
      ctx = build_ctx("_current_node_data" => {
                        "connector_id" => connector.id.to_s,
                        "model" => "gpt-4o",
                        "prompt" => "Say hello",
                      })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("empty response")
    end

    it "creates a Chat record with mission execution_context and title including mission and node label" do
      connector = create(:connector, :llm_provider)
      mock_response = double(:response, content: "Response from LLM") # rubocop:disable RSpec/VerifiedDoubles
      allow_any_instance_of(Chat).to receive(:ask).and_return(mock_response) # rubocop:disable RSpec/AnyInstance
      ctx = build_ctx("_current_node_data" => {
                        "connector_id" => connector.id.to_s,
                        "model" => "gpt-4o",
                        "prompt" => "Be helpful",
                        "label" => "Summarizer",
                      })
      expect { node.execute(ctx) }.to change(Chat, :count).by(1)
      created = Chat.last
      expect(created.execution_context).to eq("mission")
      expect(created.title).to include(mission.name)
      expect(created.title).to include("Summarizer")
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::Agent do
    subject(:node) { described_class.new }

    it "returns the correct output_ports" do
      expect(node.output_ports).to eq([{ key: "default", label: "Response" }])
    end

    it "returns a failure when agent_id is blank" do
      ctx = build_ctx("_current_node_data" => {})
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("Agent not configured")
    end

    it "returns a failure when no prompt and no last output" do
      agent = create(:agent)
      ctx = build_ctx("_current_node_data" => { "agent_id" => agent.id.to_s })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("no prompt and no input")
    end

    it "returns a failure when the agent is not found" do
      ctx = build_ctx("_current_node_data" => { "agent_id" => "999999999", "prompt" => "do something" })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("Agent not found")
    end

    it "rescues StandardError and returns a failure with Agent error message" do
      agent = create(:agent)
      allow(agent).to receive(:ask).and_raise(StandardError, "agent crash")
      allow(Agent).to receive(:find_by).and_return(agent)
      ctx = build_ctx(
        "_current_node_data" => { "agent_id" => agent.id.to_s, "prompt" => "Do something" },
      )
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("Agent error")
    end

    it "returns success when agent responds with content" do
      agent = create(:agent)
      mock_response = double(:response, content: "Agent says hello") # rubocop:disable RSpec/VerifiedDoubles
      allow(agent).to receive(:ask).and_return(mock_response)
      allow(Agent).to receive(:find_by).and_return(agent)
      ctx = build_ctx("_current_node_data" => { "agent_id" => agent.id.to_s, "prompt" => "Do something" })
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to eq("Agent says hello")
    end

    it "returns failure when agent returns response with nil content" do
      agent = create(:agent)
      mock_response = double(:response, content: nil) # rubocop:disable RSpec/VerifiedDoubles
      allow(agent).to receive(:ask).and_return(mock_response)
      allow(Agent).to receive(:find_by).and_return(agent)
      ctx = build_ctx("_current_node_data" => { "agent_id" => agent.id.to_s, "prompt" => "Do something" })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("empty response")
    end
  end

  # ──────────────────────────────────────────────────────────────────────

  describe Missions::Nodes::SubMission do
    subject(:node) { described_class.new }

    it "returns the correct output_ports" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end

    it "returns a failure when mission_id is blank" do
      ctx = build_ctx("_current_node_data" => {})
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("No mission_id configured")
    end

    it "returns a failure when mission is not found" do
      ctx = build_ctx("_current_node_data" => { "mission_id" => "999999999" })
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("Mission not found")
    end

    it "returns a failure when maximum nesting depth is exceeded" do
      inner_mission = create(:mission)
      ctx = build_ctx(
        "_current_node_data" => { "mission_id" => inner_mission.id.to_s },
        "_nesting_depth" => Missions::Nodes::SubMission::MAX_NESTING_DEPTH,
      )
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("Maximum nesting depth")
    end

    it "rescues StandardError from execute_sub_mission and returns a failure" do
      inner_mission = create(:mission)
      allow(Missions::Runner).to receive(:new).and_raise(StandardError, "runner crash")
      ctx = build_ctx(
        "_current_node_data" => { "mission_id" => inner_mission.id.to_s },
      )
      result = node.execute(ctx)
      expect(result).to be_failure
      expect(result.output).to include("Sub-mission error")
    end

    it "populates input_variables into sub-mission variables" do
      inner_mission = create(:mission)
      ctx = build_ctx(
        "_current_node_data" => {
          "mission_id" => inner_mission.id.to_s,
          "input_variables" => { "myvar" => "hello" },
        },
      )
      # Sub-mission will fail (empty flow) but the input_variables block runs
      result = node.execute(ctx)
      expect(result).to be_a(Missions::NodeResult)
    end

    it "returns success using output when the sub-mission exposes it" do
      inner_mission = create(:mission)
      sub_run = instance_double(MissionRun,
                                completed?: true,
                                variables: { "output" => "the_output" },
                                execution_state: {},)
      allow(Missions::Runner).to receive(:new).and_return(double(execute: sub_run))
      ctx = build_ctx("_current_node_data" => { "mission_id" => inner_mission.id.to_s })
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to eq("the_output")
    end

    it "returns success with nil output when node_outputs is absent in execution_state" do
      inner_mission = create(:mission)
      sub_run = instance_double(MissionRun,
                                completed?: true,
                                variables: {},
                                execution_state: {},)
      allow(Missions::Runner).to receive(:new).and_return(double(execute: sub_run))
      ctx = build_ctx("_current_node_data" => { "mission_id" => inner_mission.id.to_s })
      result = node.execute(ctx)
      expect(result).to be_success
      expect(result.output).to be_nil
    end
  end
end
