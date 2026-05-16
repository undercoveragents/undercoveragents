# frozen_string_literal: true

require "rails_helper"
require "support/mission_flow_builder"

module Missions
  module Nodes
    class AsyncNodeContextProbe
      include MissionNodePlugin

      class << self
        def node_type = "async_node_context_probe"
        def node_label = "Async Node Context Probe"
        def node_icon = "fa-solid fa-vial"
        def node_color = "#0f766e"
        def node_category = :node
        def node_description = "Test node that verifies transient node context isolation"
      end

      def execute(context)
        yield_to_scheduler

        node_data = context.get_variable("_current_node_data") || {}
        variable_name = node_data.fetch("variable_name")
        value = node_data.fetch("expected_value")

        Missions::NodeResult.new(
          status: :success,
          output: value,
          next_port: "default",
          variables: { variable_name => value },
        )
      end

      private

      def yield_to_scheduler
        Async::Task.current.yield
      rescue RuntimeError
        nil
      end
    end

    class AsyncVariableEcho
      include MissionNodePlugin

      class << self
        def node_type = "async_variable_echo"
        def node_label = "Async Variable Echo"
        def node_icon = "fa-solid fa-wave-square"
        def node_color = "#0891b2"
        def node_category = :node
        def node_description = "Test node that reads a runtime helper after yielding"
      end

      def execute(context)
        yield_to_scheduler

        node_data = context.get_variable("_current_node_data") || {}
        source_key = node_data.fetch("source_key")
        variable_name = node_data.fetch("variable_name")
        value = source_key == "current_input" ? context.current_input : context.get_variable(source_key)

        Missions::NodeResult.new(
          status: :success,
          output: value,
          next_port: "default",
          variables: { variable_name => value },
        )
      end

      private

      def yield_to_scheduler
        Async::Task.current.yield
      rescue RuntimeError
        nil
      end
    end
  end
end

RSpec.describe Missions::Runner do
  # Register test nodes before the suite runs
  before do
    # Reset and re-register to ensure clean state
    MissionNodePlugin.reset!

    MissionNodePlugin.register(
      "input", "Missions::Nodes::Input",
      label: "Input", icon: "fa-solid fa-right-to-bracket", color: "#10b981",
      category: :input_output, description: "Receives input fields from an API call",
    )
    MissionNodePlugin.register(
      "llm", "Missions::Nodes::Llm",
      label: "Generate Text", icon: "fa-solid fa-brain", color: "#6366f1",
      category: :llm, description: "Generates text using a language model",
    )
    MissionNodePlugin.register(
      "agent", "Missions::Nodes::Agent",
      label: "Agent", icon: "fa-solid fa-user-secret", color: "#4f46e5",
      category: :llm, description: "Invokes an AI agent",
    )
    MissionNodePlugin.register(
      "generate_image", "Missions::Nodes::GenerateImage",
      label: "Generate Image", icon: "fa-solid fa-image", color: "#a855f7",
      category: :llm, description: "Generates an image using an AI model",
    )
    MissionNodePlugin.register(
      "mission", "Missions::Nodes::SubMission",
      label: "Mission", icon: "fa-solid fa-diagram-project", color: "#8b5cf6",
      category: :node, description: "Calls another mission",
    )
    MissionNodePlugin.register(
      "condition", "Missions::Nodes::Condition",
      label: "Condition", icon: "fa-solid fa-code-branch", color: "#f97316",
      category: :control, description: "Branches based on condition",
    )
    MissionNodePlugin.register(
      "switch", "Missions::Nodes::Switch",
      label: "Switch", icon: "fa-solid fa-arrows-split-up-and-left", color: "#e11d48",
      category: :control, description: "Routes by value",
    )
    MissionNodePlugin.register(
      "iterator", "Missions::Nodes::Iterator",
      label: "Iterator", icon: "fa-solid fa-repeat", color: "#0ea5e9",
      category: :control, description: "Iterates over collection",
    )
    MissionNodePlugin.register(
      "loop", "Missions::Nodes::Loop",
      label: "Loop", icon: "fa-solid fa-arrows-rotate", color: "#14b8a6",
      category: :control, description: "Repeats while condition is met",
    )
    MissionNodePlugin.register(
      "set_variable", "Missions::Nodes::SetVariable",
      label: "Set Variable", icon: "fa-solid fa-equals", color: "#84cc16",
      category: :control, description: "Sets variables",
    )
    MissionNodePlugin.register(
      "output", "Missions::Nodes::Output",
      label: "Output", icon: "fa-solid fa-arrow-right-from-bracket", color: "#ec4899",
      category: :input_output, description: "Selects variables to output from the mission",
    )
    MissionNodePlugin.register(
      "aggregate", "Missions::Nodes::Aggregate",
      label: "Aggregate", icon: "fa-solid fa-calculator", color: "#7c3aed",
      category: :control, description: "Reduces an array using an aggregation operation",
    )
  end

  def duplicate_label_json_extract_flow
    MissionFlowBuilder.build do |f|
      f.node("input", type: "input", label: "Input")
      f.node("extract_a", type: "set_variable", label: "JSON Extract",
                          assignments: { "value" => "alpha" },)
      f.node("extract_b", type: "set_variable", label: "JSON Extract",
                          assignments: { "value" => "beta" },)
      f.node("combine", type: "set_variable", label: "Combine",
                        assignments: { "combined" => "CONCAT(json_extract.value, ':', json_extract_2.value)" },)
      f.node("output", type: "output", label: "Output", selected_variables: ["combine.combined"])
      f.edge("input", "extract_a")
      f.edge("input", "extract_b")
      f.edge("extract_a", "combine")
      f.edge("extract_b", "combine")
      f.edge("combine", "output")
    end
  end

  after { MissionNodePlugin.restore_defaults! }

  def build_simple_output_flow
    MissionFlowBuilder.build do |f|
      f.node("t1", type: "input")
      f.node("o1", type: "output")
      f.edge("t1", "o1")
    end
  end

  def build_join_resume_flow
    MissionFlowBuilder.build do |f|
      f.node("sv_a", type: "set_variable", assignments: { "results_a" => "1" })
      f.node("sv_b", type: "set_variable", assignments: { "results_b" => "2" })
      f.node("o1", type: "output", selected_variables: ["results_a", "results_b"])
      f.edge("sv_a", "o1")
      f.edge("sv_b", "o1")
    end
  end

  def build_execution_state(variables:, scheduler_frontiers: nil, node_arrivals: nil, execution_count: nil)
    {
      "variables" => variables,
      "node_outputs" => {},
      "execution_log" => [],
    }.tap do |state|
      state["scheduler_frontiers"] = scheduler_frontiers if scheduler_frontiers
      state["node_arrivals"] = node_arrivals if node_arrivals
      state["execution_count"] = execution_count if execution_count
    end
  end

  def build_frontier_execution_state(variables:, frontier:, execution_count:, node_arrivals: nil)
    build_execution_state(
      variables:,
      scheduler_frontiers: frontier,
      node_arrivals:,
      execution_count:,
    )
  end

  def build_frontier(frontier_id:, ready: [], active: nil)
    {
      frontier_id => {
        "ready" => ready,
        "active" => active,
      },
    }
  end

  def build_work_item(node_id:, incoming_edge_id: nil, runtime_state: {})
    {
      "node_id" => node_id,
      "incoming_edge_id" => incoming_edge_id,
      "runtime_state" => runtime_state,
    }
  end

  def build_failed_loop_execution
    Missions::NodeExecution.new(
      node_id: "loop",
      node_type: "loop",
      status: :failure,
      output: nil,
      next_port: nil,
      started_at: nil,
      finished_at: nil,
      error: "boom",
    )
  end

  def create_mission_run_for_restart(mission:, flow:, current_node_id:, execution_state:, **attributes)
    create(:mission_run,
           mission:,
           flow_snapshot: flow,
           current_node_id:,
           execution_state:,
           **attributes,)
  end

  def create_paused_frontier_run(mission:, flow:, execution_state:)
    create_mission_run_for_restart(
      mission:,
      flow:,
      current_node_id: nil,
      execution_state:,
      status: "paused",
    )
  end

  def create_failed_frontier_run(mission:, flow:, execution_state:, error:)
    create_mission_run_for_restart(
      mission:,
      flow:,
      current_node_id: nil,
      execution_state:,
      status: "failed",
      error:,
    )
  end

  def unresolved_loop_join_flow
    {
      "nodes" => [
        { "id" => "input", "type" => "input", "data" => { "label" => "Input" } },
        { "id" => "loop", "type" => "loop",
          "data" => { "label" => "Repeat Delay", "max_iterations" => 5 }, },
        { "id" => "delay", "type" => "delay",
          "data" => { "label" => "Wait 1 Second", "duration" => 1, "unit" => "seconds" }, },
        { "id" => "output", "type" => "output", "data" => { "label" => "Output" } },
      ],
      "edges" => [
        { "id" => "e1", "source" => "input", "target" => "loop", "sourceHandle" => "default" },
        { "id" => "e2", "source" => "loop", "target" => "delay", "sourceHandle" => "loop" },
        { "id" => "e3", "source" => "delay", "target" => "loop", "sourceHandle" => "default" },
        { "id" => "e4", "source" => "loop", "target" => "output", "sourceHandle" => "done" },
      ],
    }
  end

  # ══════════════════════════════════════════════════════════════════════
  # 1. BASIC LINEAR FLOW
  # ══════════════════════════════════════════════════════════════════════

  describe "linear flow execution" do
    it "executes a simple trigger → output flow" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "Hello world" })

      expect(run).to be_completed
      expect(run.variables["output"]).to eq("Hello world")
      expect(run.node_executions.size).to eq(2)
      expect(run.error).to be_nil
    end

    it "keeps a linear branch inside one traversal work loop" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "mid" => "input" })
        f.node("o1", type: "output", selected_variables: ["mid"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)
      allow(runner).to receive(:drain_scheduler).and_call_original

      run = runner.execute(variables: { "input" => "stack-safe" })

      expect(run).to be_completed
      expect(run.variables["mid"]).to eq("stack-safe")
      expect(runner).to have_received(:drain_scheduler).once
    end

    it "passes output from one node to the next through the branch input" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "greeting" => "Hello from set_variable" })
        f.node("o1", type: "output", selected_variables: ["greeting"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["greeting"]).to eq("Hello from set_variable")
    end

    it "creates a MissionRun record with proper lifecycle", :aggregate_failures do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)

      expect { runner.execute(variables: { "input" => "test" }) }.to change(MissionRun, :count).by(1)

      run = MissionRun.last
      expect(run.status).to eq("completed")
      expect(run.started_at).to be_present
      expect(run.completed_at).to be_present
      expect(run.completed_at).to be >= run.started_at
      expect(run.flow_snapshot).to eq(mission.reload.flow_data)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 2. VARIABLE MANAGEMENT
  # ══════════════════════════════════════════════════════════════════════

  describe "variable management" do
    it "passes initial variables through the flow" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["user_name", "input"])
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "Hi there", "user_name" => "Alice" },
      )

      expect(run).to be_completed
      expect(run.variables["user_name"]).to eq("Alice")
      expect(run.variables["input"]).to eq("Hi there")
    end

    it "supports expression evaluation in set_variable" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "result" => "x + y" })
        f.node("o1", type: "output", selected_variables: ["result"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "x" => 10, "y" => 25 },
      )

      expect(run).to be_completed
      expect(run.variables["result"]).to eq(35)
    end

    it "chains multiple set_variable nodes" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "a" => "5", "b" => "10" })
        f.node("sv2", type: "set_variable", assignments: { "sum" => "a + b", "product" => "a * b" })
        f.node("o1", type: "output", selected_variables: ["sum", "product"])
        f.edge("t1", "sv1")
        f.edge("sv1", "sv2")
        f.edge("sv2", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["sum"]).to eq(15)
      expect(run.variables["product"]).to eq(50)
    end

    it "selects specific variables for output" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "name" => "World" })
        f.node("o1", type: "output", selected_variables: ["name"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "Greetings" })

      expect(run).to be_completed
      expect(run.variables["name"]).to eq("World")
    end

    it "handles undefined selected variables as nil" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["defined_var", "undefined_var"])
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "defined_var" => "hello" },
      )

      expect(run).to be_completed
      expect(run.variables["defined_var"]).to eq("hello")
      expect(run.variables["undefined_var"]).to be_nil
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 3. CONDITION BRANCHING
  # ══════════════════════════════════════════════════════════════════════

  describe "condition branching" do
    let(:flow_with_condition) do
      MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "score" => "75" })
        f.node("cond", type: "condition", expression: "score > 50")
        f.node("pass", type: "set_variable", assignments: { "result" => "PASS" })
        f.node("fail", type: "set_variable", assignments: { "result" => "FAIL" })
        f.edge("t1", "sv")
        f.edge("sv", "cond")
        f.edge("cond", "pass", source_handle: "true")
        f.edge("cond", "fail", source_handle: "false")
      end
    end

    it "follows the true branch when condition is true" do
      mission = create(:mission, flow_data: flow_with_condition)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("PASS")
    end

    it "follows the false branch when condition is false" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "score" => "25" })
        f.node("cond", type: "condition", expression: "score > 50")
        f.node("pass", type: "set_variable", assignments: { "result" => "PASS" })
        f.node("fail", type: "set_variable", assignments: { "result" => "FAIL" })
        f.edge("t1", "sv")
        f.edge("sv", "cond")
        f.edge("cond", "pass", source_handle: "true")
        f.edge("cond", "fail", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("FAIL")
    end

    it "handles nested conditions" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "x" => "80", "y" => "30" })
        f.node("c1", type: "condition", expression: "x > 50")
        f.node("c2", type: "condition", expression: "y > 50")
        f.node("both_high", type: "set_variable", assignments: { "result" => "BOTH_HIGH" })
        f.node("x_high_only", type: "set_variable", assignments: { "result" => "X_HIGH_ONLY" })
        f.node("neither", type: "set_variable", assignments: { "result" => "NEITHER" })
        f.edge("t1", "sv")
        f.edge("sv", "c1")
        f.edge("c1", "c2", source_handle: "true")
        f.edge("c1", "neither", source_handle: "false")
        f.edge("c2", "both_high", source_handle: "true")
        f.edge("c2", "x_high_only", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("X_HIGH_ONLY")
    end

    it "supports equality conditions" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "status" => "42" })
        f.node("cond", type: "condition", expression: "status = 42")
        f.node("yes", type: "set_variable", assignments: { "result" => "MATCH" })
        f.node("no", type: "set_variable", assignments: { "result" => "NO_MATCH" })
        f.edge("t1", "sv")
        f.edge("sv", "cond")
        f.edge("cond", "yes", source_handle: "true")
        f.edge("cond", "no", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("MATCH")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 4. SWITCH ROUTING
  # ══════════════════════════════════════════════════════════════════════

  describe "switch routing" do
    it "routes to the matching case" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "category" => "2" })
        f.node("sw", type: "switch", expression: "category",
                     cases: { "case_a" => "1", "case_b" => "2", "case_c" => "3" },)
        f.node("a", type: "set_variable", assignments: { "result" => "ROUTE_A" })
        f.node("b", type: "set_variable", assignments: { "result" => "ROUTE_B" })
        f.node("c", type: "set_variable", assignments: { "result" => "ROUTE_C" })
        f.node("d", type: "set_variable", assignments: { "result" => "DEFAULT" })
        f.edge("t1", "sv")
        f.edge("sv", "sw")
        f.edge("sw", "a", source_handle: "case_a")
        f.edge("sw", "b", source_handle: "case_b")
        f.edge("sw", "c", source_handle: "case_c")
        f.edge("sw", "d", source_handle: "default")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("ROUTE_B")
    end

    it "routes to default when no case matches" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "category" => "99" })
        f.node("sw", type: "switch", expression: "category", cases: { "case_a" => "1", "case_b" => "2" })
        f.node("a", type: "set_variable", assignments: { "result" => "ROUTE_A" })
        f.node("b", type: "set_variable", assignments: { "result" => "ROUTE_B" })
        f.node("d", type: "set_variable", assignments: { "result" => "DEFAULT" })
        f.edge("t1", "sv")
        f.edge("sv", "sw")
        f.edge("sw", "a", source_handle: "case_a")
        f.edge("sw", "b", source_handle: "case_b")
        f.edge("sw", "d", source_handle: "default")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("DEFAULT")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 5. ITERATOR
  # ══════════════════════════════════════════════════════════════════════

  describe "iterator" do
    it "iterates over a JSON array" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["apple","banana","cherry"]')
        f.node("sv", type: "set_variable", assignments: { "processed" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done iterating" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.execution_state.dig("node_variables", "iterator", "total")).to eq(3)
    end

    it "sets item and index for each iteration" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b","c"]')
        f.node("sv", type: "set_variable", assignments: { "last_item" => "{{item}}" })
        f.node("o1", type: "output", selected_variables: ["last_item"])
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      # After iterating, last_item should be the last element processed
      expect(run.variables["last_item"]).to eq("c")
    end

    it "handles empty collections" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "[]")
        f.node("sv", type: "set_variable", assignments: { "should_not_run" => "true" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Empty collection handled" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables).not_to have_key("should_not_run")
      expect(run.variables["result"]).to eq("Empty collection handled")
    end

    it "iterates over a comma-separated string" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "red,green,blue")
        f.node("sv", type: "set_variable", assignments: { "count" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.execution_state.dig("node_variables", "iterator", "total")).to eq(3)
    end

    it "iterates over a variable reference" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "items")
        f.node("sv", type: "set_variable", assignments: { "count" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "items" => ["x", "y", "z"] },
      )

      expect(run).to be_completed
      expect(run.execution_state.dig("node_variables", "iterator", "total")).to eq(3)
    end

    it "resolves a {{node_name.variable}} template expression as collection" do
      # Regression: iterator collection configured as {{input.input}} should
      # resolve via the upstream node-scoped variables, not raise 'not defined'.
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input", name: "Input")
        f.node("iter", type: "iterator", collection: "{{input.input}}")
        f.node("sv", type: "set_variable", assignments: { "last_item" => "{{item}}" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "[1, 2]" })

      expect(run).to be_completed
      expect(run.execution_state.dig("node_variables", "iterator", "total")).to eq(2)
      expect(run.variables["last_item"]).to eq(2)
    end

    it "registers unique node prefixes when duplicate labels repeat" do
      mission = create(:mission, flow_data: duplicate_label_json_extract_flow)
      run = described_class.new(mission).execute(variables: { "input" => "go" })

      expect(run).to be_completed
      expect(run.execution_state.dig("node_variables", "json_extract", "value")).to eq("alpha")
      expect(run.execution_state.dig("node_variables", "json_extract_2", "value")).to eq("beta")
      expect(run.execution_state.dig("node_variables", "combine", "combined")).to eq("alpha:beta")
    end

    it "falls back to mission flow_data when the mission run has no flow_snapshot" do
      mission = create(:mission, flow_data: duplicate_label_json_extract_flow)
      mission_run = instance_double(MissionRun, flow_snapshot: nil, mission:)
      context = instance_double(Missions::ExecutionContext, mission_run:)

      expect(described_class.new(mission).send(:derive_node_name, context, { "label" => "JSON Extract" }, "extract_b"))
        .to eq("json_extract_2")
    end

    it "falls back to the node label when the mission run has no mission" do
      mission = create(:mission, flow_data: duplicate_label_json_extract_flow)
      mission_run = instance_double(MissionRun, flow_snapshot: nil, mission: nil)
      context = instance_double(Missions::ExecutionContext, mission_run:)

      expect(described_class.new(mission).send(:derive_node_name, context, { "label" => "JSON Extract" }, "extract_b"))
        .to eq("json_extract")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 6. LOOP
  # ══════════════════════════════════════════════════════════════════════

  describe "loop" do
    it "loops a fixed number of times" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "3")
        f.node("sv", type: "set_variable", assignments: { "tick" => "iteration" })
        f.node("o1", type: "output", selected_variables: ["tick"])
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      # Loop ran 3 times (iterations 0, 1, 2), tick should be 2 (last iteration)
      expect(run.variables["tick"]).to eq(2)
    end

    it "exits loop when condition becomes false" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv_init", type: "set_variable", assignments: { "counter" => "0" })
        f.node("lp", type: "loop", condition: "counter < 5", max_iterations: "100")
        f.node("sv_inc", type: "set_variable", assignments: { "counter" => "counter + 1" })
        f.node("o1", type: "output", selected_variables: ["counter"])
        f.edge("t1", "sv_init")
        f.edge("sv_init", "lp")
        f.edge("lp", "sv_inc", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["counter"]).to eq(5)
    end

    it "handles zero-iteration loops" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "flag" => "0" })
        f.node("lp", type: "loop", condition: "flag > 0", max_iterations: "10")
        f.node("body", type: "set_variable", assignments: { "should_not_run" => "true" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Skipped" })
        f.edge("t1", "sv")
        f.edge("sv", "lp")
        f.edge("lp", "body", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables).not_to have_key("should_not_run")
      expect(run.variables["result"]).to eq("Skipped")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 7. IMPLICIT JOINS
  # ══════════════════════════════════════════════════════════════════════

  describe "fan-out dispatch" do
    let(:runner) { described_class.new(create(:mission)) }
    let(:run) { instance_double(MissionRun) }
    let(:graph) { instance_double(Missions::FlowGraph) }
    let(:scheduler) { Missions::RunnerScheduler.start(node_id: "t1", execution_count: shared_execution_count) }
    let(:context) do
      instance_double(
        Missions::ExecutionContext,
        snapshot_runtime_state: {},
        inherit_runtime_state: nil,
        clear_runtime_state_for_current_task: nil,
      )
    end
    let(:shared_execution_count) { Missions::ExecutionCounter.new }
    let(:seen_execution_counts) { [] }
    let(:seen_incoming_edges) { [] }
    let(:edges) do
      [
        { "id" => "e1", "target" => "n1" },
        { "id" => "e2", "target" => "n2" },
      ]
    end

    before do
      allow(runner).to receive(:resolve_outgoing_edges).and_return(edges)
      allow(runner).to receive(:mark_edge_in_progress)
      allow(runner).to receive(:drain_scheduler) do |*args|
        branch_scheduler = args.last
        work_item = branch_scheduler.dequeue

        seen_execution_counts << branch_scheduler.execution_count
        seen_incoming_edges << work_item.incoming_edge_id
        sleep(0.2)
      end
    end

    it "executes same-handle branches in parallel" do
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      runner.send(:follow_edges, run, graph, context, "t1", "default", scheduler:)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      expect(runner).to have_received(:drain_scheduler).twice
      expect(seen_execution_counts).to all(be(shared_execution_count))
      expect(seen_incoming_edges).to contain_exactly("e1", "e2")
      expect(elapsed).to be < 0.35
    end
  end

  describe "concurrent execution helpers" do
    let(:runner) { described_class.new(create(:mission)) }

    it "supports concurrent execution without an execution context" do
      seen = []

      runner.send(:execute_concurrently, ["only-branch"], context: nil) do |item|
        seen << item
      end

      expect(seen).to eq(["only-branch"])
    end

    it "re-raises output completion returned by the task waiter" do
      output_reached = Missions::OutputReached.new(node_id: "o1", output_variables: { "output" => "done" })

      allow(runner).to receive_messages(
        build_concurrent_tasks: [],
        wait_for_concurrent_tasks: output_reached,
      )

      expect do
        runner.send(:execute_concurrently, [], context: nil) { nil }
      end.to raise_error(Missions::OutputReached)
    end

    it "re-raises the first task error returned by the task waiter" do
      allow(runner).to receive_messages(
        build_concurrent_tasks: [],
        wait_for_concurrent_tasks: nil,
      )

      error = StandardError.new("branch failed")
      allow(runner).to receive(:wait_for_concurrent_tasks) do |_parent_task, _tasks, errors|
        errors << error
        nil
      end

      expect do
        runner.send(:execute_concurrently, [], context: nil) { nil }
      end.to raise_error(StandardError, "branch failed")
    end

    it "collects standard task errors in the waiter" do
      parent_task = instance_double(Async::Task, stop: nil)
      task_error = StandardError.new("branch failed")
      task = instance_double(Async::Task)
      allow(task).to receive(:wait).and_raise(task_error)

      errors = []
      output_reached = runner.send(:wait_for_concurrent_tasks, parent_task, [task], errors)

      expect(output_reached).to be_nil
      expect(errors).to eq([task_error])
      expect(parent_task).not_to have_received(:stop)
    end
  end

  describe "restored frontier traversal" do
    let(:flow) { build_simple_output_flow }
    let(:mission) { create(:mission, flow_data: flow) }
    let(:runner) { described_class.new(mission) }
    let(:mission_run) { create(:mission_run, mission:, flow_snapshot: flow) }
    let(:context) { Missions::ExecutionContext.new(mission_run:) }
    let(:run) { instance_double(MissionRun) }
    let(:graph) { instance_double(Missions::FlowGraph) }

    it "returns no schedulers when no frontier state exists" do
      expect(runner.send(:restore_schedulers, context)).to eq([])
    end

    it "restores schedulers in frontier order with a shared execution counter" do
      context.sync_scheduler_frontier("frontier-b", ready_items: [build_work_item(node_id: "o1")])
      context.sync_scheduler_frontier("frontier-a", ready_items: [build_work_item(node_id: "t1")])
      context.execution_count_value = 6

      schedulers = runner.send(:restore_schedulers, context)

      expect(schedulers.map(&:frontier_id)).to eq(["frontier-a", "frontier-b"])
      expect(schedulers.map(&:execution_count).uniq.size).to eq(1)
      expect(schedulers.first.execution_count.value).to eq(6)
    end

    it "drains a single restored scheduler inline" do
      scheduler = instance_double(Missions::RunnerScheduler)
      allow(runner).to receive(:drain_scheduler)
      allow(runner).to receive(:execute_concurrently)

      runner.send(:drain_restored_schedulers, run, graph, context, [scheduler])

      expect(runner).to have_received(:drain_scheduler).with(run, graph, context, scheduler)
      expect(runner).not_to have_received(:execute_concurrently)
    end

    it "drains multiple restored schedulers concurrently" do
      scheduler_a = instance_double(Missions::RunnerScheduler)
      scheduler_b = instance_double(Missions::RunnerScheduler)
      allow(runner).to receive(:drain_scheduler)
      allow(runner).to receive(:execute_concurrently) do |items, **, &block|
        items.each(&block)
      end

      runner.send(:drain_restored_schedulers, run, graph, context, [scheduler_a, scheduler_b])

      expect(runner).to have_received(:execute_concurrently).with([scheduler_a, scheduler_b], context:)
      expect(runner).to have_received(:drain_scheduler).with(run, graph, context, scheduler_a)
      expect(runner).to have_received(:drain_scheduler).with(run, graph, context, scheduler_b)
    end

    it "routes execute_from through restored schedulers when frontier state exists" do
      scheduler = instance_double(Missions::RunnerScheduler)
      allow(runner).to receive(:restore_schedulers).with(context).and_return([scheduler])
      allow(runner).to receive(:drain_restored_schedulers)
      allow(runner).to receive(:execute_node_and_follow)

      runner.send(:execute_from, run, graph, context, "t1")

      expect(runner).to have_received(:drain_restored_schedulers).with(run, graph, context, [scheduler])
      expect(runner).not_to have_received(:execute_node_and_follow)
    end

    it "enqueues incoming edge ids when starting a node traversal" do
      scheduler = instance_double(Missions::RunnerScheduler, enqueue: nil)
      allow(runner).to receive(:build_scheduler).and_return(scheduler)
      allow(runner).to receive(:drain_scheduler)

      runner.send(:execute_node_and_follow, run, graph, context, "o1", incoming_edge: { "id" => "edge-1" })

      expect(scheduler).to have_received(:enqueue).with(
        "o1",
        incoming_edge_id: "edge-1",
        runtime_state: {},
      )
    end
  end

  describe "queue-driven control-flow helpers" do
    let(:flow) { build_simple_output_flow }
    let(:mission) { create(:mission, flow_data: flow) }
    let(:runner) { described_class.new(mission) }
    let(:mission_run) { create(:mission_run, mission:, flow_snapshot: flow) }

    it "skips iterator startup when the collection is already restored" do
      context = Missions::ExecutionContext.new(mission_run:)
      scheduler = instance_double(
        Missions::RunnerScheduler,
        execution_count: Missions::ExecutionCounter.new,
        complete_active_work_item: nil,
      )
      run = instance_double(MissionRun)
      graph = instance_double(Missions::FlowGraph)
      allow(run).to receive_messages(reload: run, cancelled?: false)

      context.set_iterator_state("iter", collection: ["saved-item"], index: 0, total: 1, results: [])
      allow(runner).to receive(:start_iterator_flow)
      allow(runner).to receive(:follow_edges)
      allow(runner).to receive(:checkpoint_active_frontier)
      allow(runner).to receive(:on_iterator_loop_done)

      runner.send(:execute_iterator_flow, run, graph, context, "iter", {}, scheduler)

      expect(runner).not_to have_received(:start_iterator_flow)
      expect(context.get_variable("results")).to eq(["saved-item"])
    end

    it "keeps the active loop work item when the last execution failed" do
      context = instance_double(
        Missions::ExecutionContext,
        execution_log: [build_failed_loop_execution],
        clear_loop_iteration: nil,
      )
      scheduler = instance_double(Missions::RunnerScheduler, complete_active_work_item: nil)
      run = instance_double(MissionRun)
      graph = instance_double(Missions::FlowGraph)
      allow(runner).to receive(:on_loop_done)
      allow(runner).to receive(:follow_edges)

      runner.send(:finish_loop?, run, graph, context, "loop", scheduler)

      expect(scheduler).not_to have_received(:complete_active_work_item)
    end

    it "completes the active loop work item when no prior loop execution exists" do
      context = instance_double(Missions::ExecutionContext, execution_log: [], clear_loop_iteration: nil)
      scheduler = instance_double(Missions::RunnerScheduler, complete_active_work_item: nil)
      run = instance_double(MissionRun)
      graph = instance_double(Missions::FlowGraph)
      allow(runner).to receive(:on_loop_done)
      allow(runner).to receive(:follow_edges)

      runner.send(:finish_loop?, run, graph, context, "loop", scheduler)

      expect(scheduler).to have_received(:complete_active_work_item)
    end
  end

  describe "transient node context isolation", :commit_db do
    before do
      MissionNodePlugin.register(
        "async_node_context_probe", "Missions::Nodes::AsyncNodeContextProbe",
        label: "Async Node Context Probe", icon: "fa-solid fa-vial", color: "#0f766e",
        category: :node, description: "Verifies per-branch node context isolation",
      )
      MissionNodePlugin.register(
        "async_variable_echo", "Missions::Nodes::AsyncVariableEcho",
        label: "Async Variable Echo", icon: "fa-solid fa-wave-square", color: "#0891b2",
        category: :node, description: "Verifies branch-local runtime helper isolation",
      )
    end

    def execute_test_flow(flow)
      mission = create(:mission, flow_data: flow)
      described_class.new(mission).execute(variables: { "input" => "test" })
    end

    def build_current_input_isolation_flow
      MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("seed", type: "set_variable", assignments: { "payload" => "source" })
        f.node(
          "probe",
          type: "async_variable_echo",
          source_key: "current_input",
          variable_name: "seen_current_input",
        )
        f.node("changer", type: "set_variable", assignments: { "changed" => "99" })
        f.edge("t1", "seed")
        f.edge("seed", "probe")
        f.edge("seed", "changer")
      end
    end

    def build_iterator_isolation_flow
      MissionFlowBuilder.build do |f|
        add_iterator_isolation_nodes(f)
        add_iterator_isolation_edges(f)
      end
    end

    def add_iterator_isolation_nodes(flow)
      flow.node("t1", type: "input")
      flow.node("seed", type: "set_variable", assignments: { "items" => "[1,2,3]" })
      flow.node("iter", type: "iterator", name: "numbers_loop", collection: "items")
      flow.node("echo", type: "async_variable_echo", source_key: "current_input", variable_name: "echoed_item")
      flow.node("sum", type: "aggregate", name: "sum_items", collection: "numbers_loop.results", operation: "sum")
      flow.node("side", type: "set_variable", assignments: { "side" => "999" })
    end

    def add_iterator_isolation_edges(flow)
      flow.edge("t1", "seed")
      flow.edge("seed", "iter")
      flow.edge("seed", "side")
      flow.edge("iter", "echo", source_handle: "loop")
      flow.edge("iter", "sum", source_handle: "done")
    end

    it "keeps _current_node_data isolated across concurrent sibling branches" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("a1", type: "async_node_context_probe", variable_name: "branch_a", expected_value: "alpha")
        f.node("a2", type: "async_node_context_probe", variable_name: "branch_b", expected_value: "beta")
        f.node("o1", type: "output", selected_variables: ["branch_a", "branch_b"])
        f.edge("t1", "a1")
        f.edge("t1", "a2")
        f.edge("a1", "o1")
        f.edge("a2", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["branch_a"]).to eq("alpha")
      expect(run.variables["branch_b"]).to eq("beta")
    end

    it "keeps current branch input isolated across concurrent sibling branches" do
      run = execute_test_flow(build_current_input_isolation_flow)

      expect(run).to be_completed
      expect(run.variables["seen_current_input"]).to eq({ "payload" => "source" })
      expect(run.variables["changed"]).to eq(99)
    end

    it "keeps iterator loop results isolated from concurrent sibling branches" do
      run = execute_test_flow(build_iterator_isolation_flow)

      expect(run).to be_completed
      expect(run.execution_state.dig("node_variables", "numbers_loop", "results")).to eq([1, 2, 3])
      expect(run.execution_state.dig("node_variables", "sum_items", "result")).to eq(6)
    end
  end

  describe "implicit joins" do
    def expect_pruned_state(run, edge_ids:, node_ids:)
      edge_ids.each do |edge_id|
        expect(run.execution_state.dig("edge_states", edge_id)).to eq("disabled")
      end

      node_ids.each do |node_id|
        expect(run.execution_state.dig("node_states", node_id, "status")).to eq("disabled")
      end
    end

    def expect_node_executed_once(run, node_id)
      expect(run.node_executions.count { |execution| execution.node_id == node_id }).to eq(1)
    end

    def build_complex_pruning_flow
      MissionFlowBuilder.build do |f|
        pruning_flow_nodes.each { |id, type, data| f.node(id, type:, **data) }
        pruning_flow_edges.each { |source, target, options| f.edge(source, target, **options) }
      end
    end

    def pruning_flow_nodes
      [
        ["prep", "set_variable", { assignments: { "base" => "'prep'" } }],
        ["cond_one", "condition", { expression: "1 > 0" }],
        ["false_bridge", "set_variable", { assignments: { "branch_one" => "'false'" } }],
        ["join_one", "set_variable", { assignments: { "join_one_ready" => "true" } }],
        ["cond_two", "condition", { expression: "1 > 0" }],
        ["true_two", "set_variable", { assignments: { "final_branch" => "'true-path'" } }],
        ["false_two", "set_variable", { assignments: { "final_branch" => "'false-path'" } }],
        ["join_two", "set_variable", { assignments: { "result" => "CONCAT(base, '-', final_branch)" } }],
        ["o1", "output", { selected_variables: ["result"] }],
      ]
    end

    def pruning_flow_edges
      [
        ["prep", "join_one", { id: "edge-prep-join_one" }],
        ["cond_one", "cond_two", { id: "edge-cond_one-true", source_handle: "true" }],
        ["cond_one", "false_bridge", { id: "edge-cond_one-false", source_handle: "false" }],
        ["false_bridge", "join_one", { id: "edge-false_bridge-join_one" }],
        ["join_one", "join_two", { id: "edge-join_one-join_two" }],
        ["cond_two", "true_two", { id: "edge-cond_two-true", source_handle: "true" }],
        ["cond_two", "false_two", { id: "edge-cond_two-false", source_handle: "false" }],
        ["true_two", "join_two", { id: "edge-true_two-join_two" }],
        ["false_two", "join_two", { id: "edge-false_two-join_two" }],
        ["join_two", "o1", { id: "edge-join_two-output" }],
      ]
    end

    it "waits for all incoming predecessors before executing a shared node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("sv_a", type: "set_variable", assignments: { "results_a" => "1" })
        f.node("sv_b", type: "set_variable", assignments: { "results_b" => "2" })
        f.node("o1", type: "output", selected_variables: ["results_a", "results_b"])
        f.edge("sv_a", "o1")
        f.edge("sv_b", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_completed
      expect(run.variables["results_a"]).to eq(1)
      expect(run.variables["results_b"]).to eq(2)
      expect(run.node_executions.count { |execution| execution.node_id == "o1" }).to eq(1)
    end

    it "counts multiple direct ports from the same condition as one predecessor signal" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition", expression: "1 > 0")
        f.node("o1", type: "output")
        f.edge("t1", "cond")
        f.edge("cond", "o1", id: "edge-cond-o1-true", source_handle: "true")
        f.edge("cond", "o1", id: "edge-cond-o1-false", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["output"]).to be(true)
      expect(run.node_executions.count { |execution| execution.node_id == "o1" }).to eq(1)
    end

    it "allows a shared continuation reached through pruned mutually exclusive branches" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition", expression: "1 > 0")
        f.node("sv_a", type: "set_variable", assignments: { "branch" => "A" })
        f.node("sv_b", type: "set_variable", assignments: { "branch" => "B" })
        f.node("o1", type: "output", selected_variables: ["branch"])
        f.edge("t1", "cond")
        f.edge("cond", "sv_a", source_handle: "true")
        f.edge("cond", "sv_b", source_handle: "false")
        f.edge("sv_a", "o1")
        f.edge("sv_b", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["branch"]).to eq("A")
      expect_pruned_state(run, edge_ids: ["e-cond-sv_b", "e-sv_b-o1"], node_ids: ["sv_b"])
      expect_node_executed_once(run, "o1")
    end

    it "handles complex branch pruning across multiple disabled edges and join releases" do
      mission = create(:mission, flow_data: build_complex_pruning_flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("prep-true-path")
      expect_pruned_state(
        run,
        edge_ids: [
          "edge-cond_one-false",
          "edge-false_bridge-join_one",
          "edge-cond_two-false",
          "edge-false_two-join_two",
        ],
        node_ids: ["false_bridge", "false_two"],
      )
      expect_node_executed_once(run, "join_one")
      expect_node_executed_once(run, "join_two")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 8. ERROR HANDLING & EDGE CASES
  # ══════════════════════════════════════════════════════════════════════

  describe "error handling" do
    it "fails gracefully when a node type is not registered" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("bad", type: "nonexistent_type")
        f.edge("t1", "bad")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("nonexistent_type")
    end

    it "runs successfully starting from root nodes when no trigger node is defined" do
      flow = MissionFlowBuilder.build do |f|
        f.node("n1", type: "set_variable", assignments: { "x" => "hello" })
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_completed
      expect(run.variables["x"]).to eq("hello")
    end

    it "fails when flow has no nodes" do
      mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("No nodes defined")
    end

    it "persists execution state on failure" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "before_fail" => "saved" })
        f.node("bad", type: "nonexistent_type")
        f.edge("t1", "sv")
        f.edge("sv", "bad")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.variables["before_fail"]).to eq("saved")
      expect(run.execution_state["execution_log"]).to be_present
    end

    it "snapshots the flow definition at execution time" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      # Modify the mission after execution
      mission.update!(flow_data: { "nodes" => [], "edges" => [] })

      # Run should still have the original flow
      expect(run.flow_snapshot["nodes"].size).to eq(2)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 9. CANCEL & RESUME
  # ══════════════════════════════════════════════════════════════════════

  describe "cancel" do
    it "cancels an active run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "running", flow_snapshot: flow)

      described_class.new(mission).cancel(run)

      run.reload
      expect(run).to be_cancelled
      expect(run.completed_at).to be_present
    end

    it "does not cancel a completed run" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "completed")

      described_class.new(mission).cancel(run)

      run.reload
      expect(run).to be_completed
    end
  end

  describe "resume" do
    it "resumes a paused run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run,
                   mission:,
                   status: "paused",
                   flow_snapshot: flow,
                   current_node_id: "o1",
                   execution_state: {
                     "variables" => { "input" => "resumed" },
                     "node_outputs" => {},
                     "execution_log" => [],
                   },)

      described_class.new(mission).resume(run)

      run.reload
      expect(run).to be_completed
      expect(run.variables["output"]).to eq("resumed")
    end

    it "raises when trying to resume a completed run" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "completed")

      expect do
        described_class.new(mission).resume(run)
      end.to raise_error(Missions::ExecutionError, /Cannot resume/)
    end

    it "resumes from a persisted scheduler frontier when current_node_id is absent" do
      flow = build_simple_output_flow

      mission = create(:mission, flow_data: flow)
      run = create_paused_frontier_run(
        mission:,
        flow:,
        execution_state: build_frontier_execution_state(
          variables: { "input" => "resumed" },
          frontier: build_frontier(
            frontier_id: "frontier-1",
            ready: [build_work_item(
              node_id: "o1",
              runtime_state: { Missions::ExecutionContextRuntimeHelpers::CURRENT_INPUT_KEY => "resumed" },
            )],
          ),
          execution_count: 4,
        ),
      )

      described_class.new(mission).resume(run)

      expect(run.reload).to be_completed
      expect(run.variables["output"]).to eq("resumed")
    end

    it "resumes implicit join scheduling from persisted frontier arrivals" do
      flow = build_join_resume_flow

      mission = create(:mission, flow_data: flow)
      run = create_paused_frontier_run(
        mission:,
        flow:,
        execution_state: build_frontier_execution_state(
          variables: { "results_a" => 1 },
          frontier: build_frontier(
            frontier_id: "frontier-b",
            ready: [build_work_item(node_id: "sv_b")],
          ),
          execution_count: 2,
          node_arrivals: { "o1" => ["e-sv_a-o1"] },
        ),
      )

      described_class.new(mission).resume(run)

      expect(run.reload).to be_completed
      expect(run.variables["results_a"]).to eq(1)
      expect(run.variables["results_b"]).to eq(2)
      expect(run.node_executions.count { |execution| execution.node_id == "o1" }).to eq(1)
    end
  end

  describe "retry_from_failure" do
    it "retries from the failed node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run,
                   mission:,
                   status: "failed",
                   error: "Previous error",
                   flow_snapshot: flow,
                   current_node_id: "o1",
                   execution_state: {
                     "variables" => { "input" => "retry_test" },
                     "node_outputs" => {},
                     "execution_log" => [],
                   },)

      described_class.new(mission).retry_from_failure(run)

      run.reload
      expect(run).to be_completed
      expect(run.error).to be_nil
      expect(run.variables["output"]).to eq("retry_test")
    end

    it "raises when trying to retry a non-failed run" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "completed")

      expect do
        described_class.new(mission).retry_from_failure(run)
      end.to raise_error(Missions::ExecutionError, /only retry failed/)
    end

    it "retries an active work item restored from persisted frontier state" do
      flow = build_simple_output_flow

      mission = create(:mission, flow_data: flow)
      run = create_failed_frontier_run(
        mission:,
        flow:,
        execution_state: build_frontier_execution_state(
          variables: { "input" => "retry_test" },
          frontier: build_frontier(
            frontier_id: "frontier-1",
            active: build_work_item(
              node_id: "o1",
              runtime_state: { Missions::ExecutionContextRuntimeHelpers::CURRENT_INPUT_KEY => "retry_test" },
            ),
          ),
          execution_count: 5,
        ),
        error: "Previous error",
      )

      described_class.new(mission).retry_from_failure(run)

      expect(run.reload).to be_completed
      expect(run.error).to be_nil
      expect(run.variables["output"]).to eq("retry_test")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 10. SUB-MISSION (NESTED WORKFLOWS)
  # ══════════════════════════════════════════════════════════════════════

  describe "sub-mission execution" do
    it "executes a nested mission" do
      # Inner mission: input → set_variable → output
      inner_flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "inner_result" => "processed" })
        f.node("o1", type: "output", selected_variables: ["inner_result"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end
      inner_mission = create(:mission, name: "Inner Mission", flow_data: inner_flow)

      # Outer mission: input → sub_mission → output
      outer_flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sub", type: "mission", mission_id: inner_mission.id.to_s)
        f.node("o1", type: "output")
        f.edge("t1", "sub")
        f.edge("sub", "o1")
      end
      outer_mission = create(:mission, name: "Outer Mission", flow_data: outer_flow)

      run = described_class.new(outer_mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      # The sub-mission's output node collects selected variables into a hash
      expect(run.variables["output"]).to include({ "inner_result" => "processed" })
    end

    it "fails when referenced mission does not exist" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sub", type: "mission", mission_id: "99999")
        f.edge("t1", "sub")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("Mission not found")
    end

    it "prevents infinite nesting" do
      # Create a mission that calls itself
      mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })

      self_referencing_flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sub", type: "mission", mission_id: mission.id.to_s)
        f.edge("t1", "sub")
      end
      mission.update!(flow_data: self_referencing_flow)

      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("nesting depth")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 11. COMPLEX WORKFLOW SCENARIOS
  # ══════════════════════════════════════════════════════════════════════

  describe "complex workflows" do
    it "handles condition → loop → output pipeline" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "run_loop" => "1", "counter" => "0" })
        f.node("cond", type: "condition", expression: "run_loop = 1")
        f.node("lp", type: "loop", condition: "counter < 3", max_iterations: "10")
        f.node("inc", type: "set_variable", assignments: { "counter" => "counter + 1" })
        f.node("o1", type: "output", selected_variables: ["counter"])
        f.node("o2", type: "set_variable", assignments: { "result" => "Skipped loop" })
        f.edge("t1", "sv")
        f.edge("sv", "cond")
        f.edge("cond", "lp", source_handle: "true")
        f.edge("cond", "o2", source_handle: "false")
        f.edge("lp", "inc", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["counter"]).to eq(3)
    end

    it "handles switch branching without invalid reconvergence" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "lang" => "2" })
        f.node("sw", type: "switch", expression: "lang", cases: { "en" => "1", "fr" => "2", "de" => "3" })
        f.node("en_sv", type: "set_variable", assignments: { "greeting" => "Hello" })
        f.node("fr_sv", type: "set_variable", assignments: { "greeting" => "Bonjour" })
        f.node("de_sv", type: "set_variable", assignments: { "greeting" => "Hallo" })
        f.edge("t1", "sv")
        f.edge("sv", "sw")
        f.edge("sw", "en_sv", source_handle: "en")
        f.edge("sw", "fr_sv", source_handle: "fr")
        f.edge("sw", "de_sv", source_handle: "de")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["greeting"]).to eq("Bonjour")
    end

    it "handles iterator with inner condition" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "[1,2,3,4,5]")
        f.node("cond", type: "condition", expression: "item > 3")
        f.node("sv_high", type: "set_variable", assignments: { "high_count" => "high_count + 1" })
        f.node("sv_low", type: "set_variable", assignments: { "low_count" => "low_count + 1" })
        f.node("o1", type: "output", selected_variables: ["high_count", "low_count"])
        f.edge("t1", "iter")
        f.edge("iter", "cond", source_handle: "loop")
        f.edge("cond", "sv_high", source_handle: "true")
        f.edge("cond", "sv_low", source_handle: "false")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "high_count" => 0, "low_count" => 0 },
      )

      expect(run).to be_completed
      expect(run.variables["high_count"]).to eq(2) # 4 and 5
      expect(run.variables["low_count"]).to eq(3) # 1, 2, and 3
    end

    it "handles deeply nested conditions (5 levels)" do # rubocop:disable RSpec/ExampleLength
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: {
                 "a" => "1", "b" => "1", "c" => "1", "d" => "1", "e" => "0",
               },)
        f.node("c1", type: "condition", expression: "a = 1")
        f.node("c2", type: "condition", expression: "b = 1")
        f.node("c3", type: "condition", expression: "c = 1")
        f.node("c4", type: "condition", expression: "d = 1")
        f.node("c5", type: "condition", expression: "e = 1")
        f.node("deep_yes", type: "set_variable", assignments: { "result" => "ALL_TRUE" })
        f.node("deep_no", type: "set_variable", assignments: { "result" => "NOT_ALL" })
        f.node("f1", type: "set_variable", assignments: { "result" => "FAIL_1" })
        f.node("f2", type: "set_variable", assignments: { "result" => "FAIL_2" })
        f.node("f3", type: "set_variable", assignments: { "result" => "FAIL_3" })
        f.node("f4", type: "set_variable", assignments: { "result" => "FAIL_4" })
        f.edge("t1", "sv")
        f.edge("sv", "c1")
        f.edge("c1", "c2", source_handle: "true")
        f.edge("c1", "f1", source_handle: "false")
        f.edge("c2", "c3", source_handle: "true")
        f.edge("c2", "f2", source_handle: "false")
        f.edge("c3", "c4", source_handle: "true")
        f.edge("c3", "f3", source_handle: "false")
        f.edge("c4", "c5", source_handle: "true")
        f.edge("c4", "f4", source_handle: "false")
        f.edge("c5", "deep_yes", source_handle: "true")
        f.edge("c5", "deep_no", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      # e = 0, so c5 should be false → "NOT_ALL"
      expect(run.variables["result"]).to eq("NOT_ALL")
    end

    it "handles loop with condition inside" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv_init", type: "set_variable", assignments: { "i" => "0", "small" => "0", "big" => "0" })
        f.node("lp", type: "loop", condition: "i < 6", max_iterations: "10")
        f.node("cond", type: "condition", expression: "i < 3")
        f.node("sv_small", type: "set_variable",
                           assignments: { "small" => "small + 1", "i" => "i + 1" },)
        f.node("sv_big", type: "set_variable",
                         assignments: { "big" => "big + 1", "i" => "i + 1" },)
        f.node("o1", type: "output", selected_variables: ["small", "big"])
        f.edge("t1", "sv_init")
        f.edge("sv_init", "lp")
        f.edge("lp", "cond", source_handle: "loop")
        f.edge("cond", "sv_small", source_handle: "true")
        f.edge("cond", "sv_big", source_handle: "false")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["small"]).to eq(3) # i=0, 1, 2
      expect(run.variables["big"]).to eq(3)   # i=3, 4, 5
    end

    it "keeps nested loop iteration state isolated per loop node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv_init", type: "set_variable", assignments: {
                 "counter" => "0",
                 "inner_done" => "0",
               },)
        f.node("outer", type: "loop", condition: "iteration < 3", max_iterations: "3")
        f.node("inner", type: "loop", condition: "iteration < 3", max_iterations: "3")
        f.node("sv_inc", type: "set_variable", assignments: { "counter" => "counter + 1" })
        f.node("sv_inner_done", type: "set_variable", assignments: { "inner_done" => "inner_done + 1" })
        f.node("o1", type: "output", selected_variables: ["counter", "inner_done"])
        f.edge("t1", "sv_init")
        f.edge("sv_init", "outer")
        f.edge("outer", "inner", source_handle: "loop")
        f.edge("inner", "sv_inc", source_handle: "loop")
        f.edge("inner", "sv_inner_done", source_handle: "done")
        f.edge("outer", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["counter"]).to eq(9)
      expect(run.variables["inner_done"]).to eq(3)
      expect(run.node_executions.count { |execution| execution.node_id == "sv_inc" }).to eq(9)
    end

    it "handles a multi-trigger flow" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("t2", type: "input")
        f.node("o1", type: "set_variable", assignments: { "result" => "First" })
        f.node("o2", type: "set_variable", assignments: { "result" => "Second" })
        f.edge("t1", "o1")
        f.edge("t2", "o2")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      # Both triggers execute, so both outputs run
      expect(run.variables["result"]).to eq("Second")
    end

    it "handles trigger_data as additional variables" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["channel"])
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test" },
        trigger_data: { "channel" => "telegram" },
      )

      expect(run).to be_completed
      expect(run.variables["channel"]).to eq("telegram")
    end

    it "sets _trigger_data as a hash variable for the Input node" do
      fields = [{ "variable_name" => "name", "field_type" => "string", "required" => true }]
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input", fields:)
        f.node("o1", type: "output", selected_variables: ["name"])
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        trigger_data: { "name" => "Alice" },
      )

      expect(run).to be_completed
      expect(run.variables["name"]).to eq("Alice")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 12. EXECUTION STATE & AUDIT TRAIL
  # ══════════════════════════════════════════════════════════════════════

  describe "execution state tracking" do
    it "records all node executions in the log", :aggregate_failures do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "output")
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      executions = run.node_executions
      expect(executions.size).to eq(3)
      expect(executions.map(&:node_id)).to eq(["t1", "sv", "o1"])
      expect(executions.map(&:node_type)).to eq(["input", "set_variable", "output"])
      expect(executions.all? { |e| e.status == :success }).to be true
      expect(executions.all? { |e| e.started_at.present? }).to be true
      expect(executions.all? { |e| e.finished_at.present? }).to be true
    end

    it "tracks node outputs in execution state" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "set_variable", assignments: { "result" => "Hello" })
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "World" })

      node_outputs = run.execution_state["node_outputs"]
      expect(node_outputs).to have_key("t1")
      expect(node_outputs).to have_key("o1")
    end

    it "tracks resolved node inputs in execution state" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "greeting" => "Hello {{name}}" })
        f.edge("t1", "sv1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "ignored", "name" => "Alice" })

      execution = run.node_executions.find { |entry| entry.node_id == "sv1" }
      expect(execution.input).to eq({ "assignments" => { "greeting" => "Hello Alice" } })
    end

    it "preserves run duration" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run.duration).to be >= 0
      expect(run.duration).to be < 10 # Should complete very fast
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 13. SAFETY GUARDS
  # ══════════════════════════════════════════════════════════════════════

  describe "safety guards" do
    it "enforces maximum total executions" do
      # Create a loop that would run forever without the guard
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "999999")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "output")
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)

      # Lower the limit for testing
      stub_const("Missions::Runner::MAX_TOTAL_EXECUTIONS", 50)
      stub_const("Missions::Runner::MAX_LOOP_ITERATIONS", 1000)

      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("Maximum total executions")
    end

    it "enforces maximum loop iterations" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "5000")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "output")
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)

      # The loop node internally caps at MAX_ITERATIONS = 1000
      # and Runner uses MAX_LOOP_ITERATIONS too
      stub_const("Missions::Nodes::Loop::MAX_ITERATIONS", 5)

      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.node_executions.count { |execution| execution.node_id == "sv" }).to eq(5)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 14. EXPRESSION EVALUATION
  # ══════════════════════════════════════════════════════════════════════

  describe "expression evaluation" do
    it "evaluates arithmetic expressions" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: {
                 "sum" => "a + b",
                 "diff" => "a - b",
                 "product" => "a * b",
                 "quotient" => "a / b",
               },)
        f.node("o1", type: "output", selected_variables: ["sum", "diff", "product", "quotient"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "a" => 20, "b" => 5 },
      )

      expect(run).to be_completed
      expect(run.variables["sum"]).to eq(25)
      expect(run.variables["diff"]).to eq(15)
      expect(run.variables["product"]).to eq(100)
      expect(run.variables["quotient"].to_f).to eq(4.0)
    end

    it "evaluates comparison expressions in conditions" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition", expression: "temperature >= 100")
        f.node("hot", type: "set_variable", assignments: { "result" => "HOT" })
        f.node("cold", type: "set_variable", assignments: { "result" => "COLD" })
        f.edge("t1", "cond")
        f.edge("cond", "hot", source_handle: "true")
        f.edge("cond", "cold", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "temperature" => 150 },
      )

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("HOT")
    end

    it "evaluates boolean logic" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition", expression: "x > 5 and y < 20")
        f.node("yes", type: "set_variable", assignments: { "result" => "YES" })
        f.node("no", type: "set_variable", assignments: { "result" => "NO" })
        f.edge("t1", "cond")
        f.edge("cond", "yes", source_handle: "true")
        f.edge("cond", "no", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "x" => 10, "y" => 15 },
      )

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("YES")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 15. FLOW GRAPH VALIDATION
  # ══════════════════════════════════════════════════════════════════════

  describe "FlowGraph" do
    it "identifies trigger nodes" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("n1", type: "llm")
        f.node("o1", type: "output")
      end

      graph = Missions::FlowGraph.new(flow)
      triggers = graph.trigger_nodes
      expect(triggers.size).to eq(1)
      expect(triggers.first["id"]).to eq("t1")
    end

    it "identifies output nodes" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.node("o2", type: "output")
      end

      graph = Missions::FlowGraph.new(flow)
      outputs = graph.output_nodes
      expect(outputs.size).to eq(2)
    end

    it "computes successors and predecessors" do
      flow = MissionFlowBuilder.build do |f|
        f.node("a", type: "input")
        f.node("b", type: "set_variable")
        f.node("c", type: "output")
        f.edge("a", "b")
        f.edge("b", "c")
      end

      graph = Missions::FlowGraph.new(flow)
      expect(graph.successors("a")).to eq(["b"])
      expect(graph.successors("b")).to eq(["c"])
      expect(graph.predecessors("c")).to eq(["b"])
      expect(graph.predecessors("a")).to eq([])
    end

    it "filters successors by port" do
      flow = MissionFlowBuilder.build do |f|
        f.node("cond", type: "condition")
        f.node("yes", type: "output")
        f.node("no", type: "output")
        f.edge("cond", "yes", source_handle: "true")
        f.edge("cond", "no", source_handle: "false")
      end

      graph = Missions::FlowGraph.new(flow)
      expect(graph.successors("cond", port: "true")).to eq(["yes"])
      expect(graph.successors("cond", port: "false")).to eq(["no"])
      expect(graph.successors("cond")).to eq(["yes", "no"])
    end

    it "validates flow with no entry point (all nodes form a cycle)" do
      flow = {
        "nodes" => [
          { "id" => "a", "type" => "llm", "data" => {} },
          { "id" => "b", "type" => "llm", "data" => {} },
        ],
        "edges" => [
          { "id" => "e1", "source" => "a", "target" => "b" },
          { "id" => "e2", "source" => "b", "target" => "a" },
        ],
      }

      graph = Missions::FlowGraph.new(flow)
      expect { graph.validate! }.to raise_error(Missions::InvalidFlowError, /No entry point found/)
    end

    it "validates empty flow" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })
      expect { graph.validate! }.to raise_error(Missions::InvalidFlowError, /No nodes defined/)
    end

    it "performs topological sort" do
      flow = MissionFlowBuilder.build do |f|
        f.node("a", type: "input")
        f.node("b", type: "set_variable")
        f.node("c", type: "output")
        f.edge("a", "b")
        f.edge("b", "c")
      end

      graph = Missions::FlowGraph.new(flow)
      sorted = graph.topological_sort
      expect(sorted).to eq(["a", "b", "c"])
    end

    it "finds root and leaf nodes" do
      flow = MissionFlowBuilder.build do |f|
        f.node("a", type: "input")
        f.node("b", type: "set_variable")
        f.node("c", type: "output")
        f.edge("a", "b")
        f.edge("b", "c")
      end

      graph = Missions::FlowGraph.new(flow)
      expect(graph.root_nodes.pluck("id")).to eq(["a"])
      expect(graph.leaf_nodes.pluck("id")).to eq(["c"])
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 16. EXECUTION CONTEXT
  # ══════════════════════════════════════════════════════════════════════

  describe "ExecutionContext" do
    let(:mission) { create(:mission) }
    let(:run) { create(:mission_run, mission:) }

    it "manages variables with normalized keys" do
      ctx = Missions::ExecutionContext.new(mission_run: run)
      ctx.set_variable("MyVar", "hello")
      expect(ctx.get_variable("myvar")).to eq("hello")
      expect(ctx.get_variable("MyVar")).to eq("hello")
    end

    it "evaluates expressions" do
      ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "x" => 10, "y" => 20 })
      expect(ctx.evaluate("x + y")).to eq(30)
      expect(ctx.evaluate("x * y")).to eq(200)
      expect(ctx.evaluate("x > y")).to be false
    end

    it "returns nil for invalid expressions" do
      ctx = Missions::ExecutionContext.new(mission_run: run)
      expect(ctx.evaluate("invalid +++ expr")).to be_nil
    end

    it "interpolates variables in templates" do
      ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "name" => "Alice", "age" => 30 })
      result = ctx.interpolate("Hello {{name}}, you are {{age}} years old")
      expect(result).to eq("Hello Alice, you are 30 years old")
    end

    it "preserves missing variable placeholders" do
      ctx = Missions::ExecutionContext.new(mission_run: run)
      result = ctx.interpolate("Hello {{missing}}")
      expect(result).to eq("Hello {{missing}}")
    end

    it "serializes and restores state" do
      ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "x" => 42 })
      ctx.store_node_output("node1", "result1")
      ctx.log_execution(Missions::NodeExecution.new(
                          node_id: "node1", node_type: "test", status: :success,
                          input: { "prompt" => "Hello Alice" },
                          output: "result1", next_port: "default",
                          started_at: Time.current, finished_at: Time.current, error: nil,
                        ))

      state = ctx.to_h
      restored = Missions::ExecutionContext.restore(mission_run: run, state:)

      expect(restored.get_variable("x")).to eq(42)
      expect(restored.get_node_output("node1")).to eq("result1")
      expect(restored.execution_log.size).to eq(1)
      expect(restored.execution_log.first.input).to eq({ "prompt" => "Hello Alice" })
    end

    it "handles complex object variables without direct expression evaluation" do
      ctx = Missions::ExecutionContext.new(mission_run: run)
      ctx.set_variable("data", { "key" => "value" })
      expect(ctx.get_variable("data")).to eq({ "key" => "value" })
      # The expression engine can't evaluate complex objects, but they're still stored
      expect(ctx.evaluate("data")).to be_nil
    end

    it "merges multiple variables at once" do
      ctx = Missions::ExecutionContext.new(mission_run: run)
      ctx.merge_variables({ "a" => 1, "b" => 2, "c" => 3 })
      expect(ctx.get_variable("a")).to eq(1)
      expect(ctx.get_variable("b")).to eq(2)
      expect(ctx.get_variable("c")).to eq(3)
    end

    it "keeps transient node variables task-local under Async" do
      ctx = Missions::ExecutionContext.new(mission_run: run)

      Async do |task|
        cached_state = {}
        task_store = {}.compare_by_identity
        task_store[ctx] = cached_state
        task.instance_variable_set(Missions::ExecutionContext::TASK_TRANSIENT_STATE_IVAR, task_store)

        expect(ctx.send(:transient_state_for_current_task)).to be(cached_state)
        expect(ctx.get_variable("_current_node_data")).to be_nil
        ctx.set_variable("_current_node_data", { "value" => "branch-specific" })
        expect(ctx.get_variable("_current_node_data")).to eq({ "value" => "branch-specific" })
      end.wait

      expect(ctx.get_variable("_current_node_data")).to be_nil
      expect(ctx.variables).not_to have_key("_current_node_data")
    end

    it "returns nil for current_async_task when Async is unavailable" do
      ctx = Missions::ExecutionContext.new(mission_run: run)

      hide_const("Async")

      expect(ctx.send(:current_async_task)).to be_nil
    end

    it "tracks edge states through serialization and restore" do
      ctx = Missions::ExecutionContext.new(mission_run: run)
      ctx.set_edge_state("edge-1", "in_progress")

      restored = Missions::ExecutionContext.restore(mission_run: run, state: ctx.to_h)

      expect(restored.get_edge_state("edge-1")).to eq("in_progress")
    end

    it "tracks node arrivals through serialization and restore" do
      ctx = Missions::ExecutionContext.new(mission_run: run)
      ctx.record_node_arrival("node-1", "edge-a")

      restored = Missions::ExecutionContext.restore(mission_run: run, state: ctx.to_h)

      expect(restored.node_arrivals_for("node-1")).to eq(["edge-a"])
    end

    it "ignores blank node arrivals and deduplicates repeated edges" do
      ctx = Missions::ExecutionContext.new(mission_run: run)

      ctx.record_node_arrival(nil, "edge-a")
      ctx.record_node_arrival("node-1", nil)
      ctx.record_node_arrival("node-1", "edge-a")
      ctx.record_node_arrival("node-1", "edge-a")

      expect(ctx.node_arrivals_for("node-1")).to eq(["edge-a"])
    end

    it "returns empty iterator state for blank ids and ignores clearing empty iterator state" do
      ctx = Missions::ExecutionContext.new(mission_run: run)

      expect(ctx.iterator_state(nil)).to eq({})

      ctx.clear_iterator_state(nil)
      ctx.clear_iterator_state("iter-1")

      expect(ctx.iterator_state("iter-1")).to eq({})
    end
  end

  describe "edge state guards" do
    let(:mission) { create(:mission) }
    let(:runner) { described_class.new(mission) }
    let(:mission_run) { create(:mission_run, mission:) }

    it "ignores blank edge ids when setting edge state" do
      context = Missions::ExecutionContext.new(mission_run:)

      allow(runner).to receive(:edge_state_changed)
      runner.send(:set_edge_state, mission_run, context, nil, "completed")

      expect(runner).not_to have_received(:edge_state_changed)
    end

    it "does not rebroadcast an unchanged edge state" do
      context = Missions::ExecutionContext.new(mission_run:)

      allow(runner).to receive(:edge_state_changed)

      runner.send(:set_edge_state, mission_run, context, "edge-1", "completed")
      runner.send(:set_edge_state, mission_run, context, "edge-1", "completed")

      expect(runner).to have_received(:edge_state_changed).once
    end
  end

  describe "join barrier helpers" do
    let(:mission) { create(:mission) }
    let(:runner) { described_class.new(mission) }
    let(:mission_run) { create(:mission_run, mission:) }

    it "treats a root node as immediately ready" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [{ "id" => "n1", "type" => "output", "data" => {} }],
                                        "edges" => [],
                                      })
      context = Missions::ExecutionContext.new(mission_run:)

      expect(runner.send(:node_ready_to_execute?, mission_run, graph, context, "n1", nil)).to be true
    end

    it "ignores fully satisfied joins when collecting pending barriers" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => {} },
                                          { "id" => "b", "type" => "set_variable", "data" => {} },
                                          { "id" => "o1", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [
                                          { "id" => "edge-a", "source" => "a", "target" => "o1",
                                            "sourceHandle" => "default", },
                                          { "id" => "edge-b", "source" => "b", "target" => "o1",
                                            "sourceHandle" => "default", },
                                        ],
                                      })
      context = Missions::ExecutionContext.new(mission_run:)
      context.record_node_arrival("o1", "a")
      context.record_node_arrival("o1", "b")

      expect(runner.send(:pending_join_barriers, graph, context)).to eq([])
    end

    it "treats multiple direct ports from one predecessor as a satisfied join" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "cond", "type" => "condition", "data" => {} },
                                          { "id" => "o1", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [
                                          { "id" => "edge-true", "source" => "cond", "target" => "o1",
                                            "sourceHandle" => "true", },
                                          { "id" => "edge-false", "source" => "cond", "target" => "o1",
                                            "sourceHandle" => "false", },
                                        ],
                                      })
      context = Missions::ExecutionContext.new(mission_run:)

      expect(
        runner.send(:node_ready_to_execute?, mission_run, graph, context, "o1", graph.incoming_edges("o1").first),
      ).to be(true)
    end

    it "records arrivals and defers a join while active predecessors are still missing" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => {} },
                                          { "id" => "b", "type" => "set_variable", "data" => {} },
                                          { "id" => "o1", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [
                                          { "id" => "edge-a", "source" => "a", "target" => "o1" },
                                          { "id" => "edge-b", "source" => "b", "target" => "o1" },
                                        ],
                                      })
      context = Missions::ExecutionContext.new(mission_run:)

      expect(
        runner.send(:node_ready_to_execute?, mission_run, graph, context, "o1", graph.incoming_edges("o1").first),
      ).to be(false)
      expect(context.node_arrivals_for("o1")).to eq(["a"])
    end

    it "raises an unresolved join error when active predecessors never arrive" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => { "label" => "A" } },
                                          { "id" => "b", "type" => "set_variable", "data" => { "label" => "B" } },
                                          { "id" => "o1", "type" => "output", "data" => { "label" => "Join" } },
                                        ],
                                        "edges" => [
                                          { "id" => "edge-a", "source" => "a", "target" => "o1" },
                                          { "id" => "edge-b", "source" => "b", "target" => "o1" },
                                        ],
                                      })
      context = Missions::ExecutionContext.new(mission_run:)
      context.record_node_arrival("o1", "a")
      expected_message = Regexp.new(
        "multiple active incoming predecessors.*Disabled edges do not block downstream joins",
      )

      expect { runner.send(:ensure_no_pending_joins!, graph, context) }
        .to raise_error(Missions::ExecutionError, expected_message)
    end

    it "falls back to the graph edge source when the incoming edge omits it" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "cond", "type" => "condition", "data" => {} },
                                          { "id" => "o1", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [{ "id" => "edge-1", "source" => "cond", "target" => "o1" }],
                                      })

      expect(runner.send(:join_predecessor_id, graph, { "id" => "edge-1", "source" => nil })).to eq("cond")
    end

    it "returns nil when join predecessor lookup has no inline or persisted source" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })

      expect(runner.send(:join_predecessor_id, graph, { "id" => "missing", "source" => nil })).to be_nil
    end

    it "returns nil when join predecessor lookup receives a blank edge" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })

      expect(runner.send(:join_predecessor_id, graph, nil)).to be_nil
    end

    it "does not build pending barriers for single-predecessor nodes" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => {} },
                                          { "id" => "o1", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [{ "id" => "edge-a", "source" => "a", "target" => "o1" }],
                                      })

      context = instance_double(Missions::ExecutionContext)
      allow(context).to receive(:get_edge_state)

      expect(runner.send(:build_pending_join_barrier, graph, context, "o1", ["a"])).to be_nil
    end

    it "does not record node arrivals when the predecessor cannot be resolved" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })
      context = instance_double(Missions::ExecutionContext)
      allow(context).to receive(:record_node_arrival)

      runner.send(:record_node_arrival, graph, context, "o1", { "id" => "missing", "source" => nil })

      expect(context).not_to have_received(:record_node_arrival)
    end

    it "records node arrivals when the predecessor can be resolved" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [],
                                        "edges" => [{ "id" => "edge-1", "source" => "source-node", "target" => "o1" }],
                                      })
      context = instance_double(Missions::ExecutionContext)
      allow(context).to receive(:record_node_arrival)

      runner.send(:record_node_arrival, graph, context, "o1", { "id" => "edge-1", "source" => nil })

      expect(context).to have_received(:record_node_arrival).with("o1", "source-node")
    end

    it "falls back to the node id when a join target has no label" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [{ "id" => "o1", "type" => "output", "data" => {} }],
                                        "edges" => [],
                                      })

      expect(runner.send(:join_barrier_label, graph, "o1")).to eq("o1")
    end
  end

  describe "branch pruning helpers" do
    let(:mission) { create(:mission) }
    let(:runner) { described_class.new(mission) }
    let(:mission_run) { create(:mission_run, mission:) }
    let(:context) { Missions::ExecutionContext.new(mission_run:) }
    let(:scheduler) { instance_double(Missions::RunnerScheduler, enqueue: nil) }

    it "returns false for unknown mutually exclusive node types" do
      expect(runner.send(:mutually_exclusive_output_node?, "does_not_exist")).to be(false)
    end

    it "ignores blank edges when pruning a disabled branch" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })

      expect do
        runner.send(
          :disable_edge_branch!,
          mission_run,
          graph,
          context,
          nil,
          scheduler,
          visited_edges: Set.new,
          visited_nodes: Set.new,
        )
      end.not_to raise_error
    end

    it "skips disabling edges without a usable identifier" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })

      runner.send(
        :disable_edge_branch!,
        mission_run,
        graph,
        context,
        { "id" => nil, "target" => "node-1" },
        scheduler,
        visited_edges: Set.new,
        visited_nodes: Set.new,
      )

      expect(context.get_edge_state("")).to be_nil
    end

    it "stops pruning when a disabled edge has no target node" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })

      runner.send(
        :disable_edge_branch!,
        mission_run,
        graph,
        context,
        { "id" => "edge-1", "target" => nil },
        scheduler,
        visited_edges: Set.new,
        visited_nodes: Set.new,
      )

      expect(context.get_edge_state("edge-1")).to eq("disabled")
    end

    it "skips restoring edges that were already visited" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })
      context.set_edge_state("edge-1", "disabled")

      runner.send(
        :restore_edge_branch!,
        graph,
        context,
        { "id" => "edge-1", "target" => "node-1" },
        visited_edges: Set["edge-1"],
        visited_nodes: Set.new,
      )

      expect(context.get_edge_state("edge-1")).to eq("disabled")
    end

    it "restores an edge state even when the edge has no target" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })
      context.set_edge_state("edge-2", "disabled")

      runner.send(
        :restore_edge_branch!,
        graph,
        context,
        { "id" => "edge-2", "target" => nil },
        visited_edges: Set.new,
        visited_nodes: Set.new,
      )

      expect(context.get_edge_state("edge-2")).to be_nil
    end

    it "keeps a disabled node state when no enabled incoming edges remain" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [{ "id" => "node-1", "type" => "output", "data" => {} }],
                                        "edges" => [],
                                      })
      context.set_node_state("node-1", "disabled", node_type: "output")

      runner.send(:restore_target_node_state, graph, context, "node-1")

      expect(context.get_node_state("node-1").to_h).to include("status" => "disabled")
    end

    it "ignores blank node ids when disabling node branches" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })

      runner.send(
        :disable_node_branch!,
        mission_run,
        graph,
        context,
        nil,
        scheduler,
        visited_edges: Set.new,
        visited_nodes: Set.new,
      )

      expect(context.get_node_state("").to_h).to eq({})
    end

    it "stops disabling a branch when the target node does not exist" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })

      runner.send(
        :disable_node_branch!,
        mission_run,
        graph,
        context,
        "missing-node",
        scheduler,
        visited_edges: Set.new,
        visited_nodes: Set.new,
      )

      expect(context.get_node_state("missing-node").to_h).to eq({})
    end

    it "does not rebroadcast an unchanged runtime node state" do
      context.set_node_state("node-1", "disabled", node_type: "output")
      allow(runner).to receive(:node_state_changed)

      runner.send(:set_runtime_node_state, mission_run, context, "node-1", "disabled", node_type: "output")

      expect(runner).not_to have_received(:node_state_changed)
    end

    it "does not wake a join that is already runtime-disabled" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => {} },
                                          { "id" => "join", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [{ "id" => "edge-a", "source" => "a", "target" => "join" }],
                                      })
      context.set_node_state("join", "disabled", node_type: "output")
      context.record_node_arrival("join", "a")

      runner.send(:wake_join_if_unblocked!, graph, context, "join", scheduler)

      expect(scheduler).not_to have_received(:enqueue)
    end

    it "does not wake a join when every incoming edge is disabled" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => {} },
                                          { "id" => "join", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [{ "id" => "edge-a", "source" => "a", "target" => "join" }],
                                      })
      context.record_node_arrival("join", "a")
      context.set_edge_state("edge-a", "disabled")

      runner.send(:wake_join_if_unblocked!, graph, context, "join", scheduler)

      expect(scheduler).not_to have_received(:enqueue)
    end

    it "does not wake a join until all active predecessors have arrived" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => {} },
                                          { "id" => "b", "type" => "set_variable", "data" => {} },
                                          { "id" => "join", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [
                                          { "id" => "edge-a", "source" => "a", "target" => "join" },
                                          { "id" => "edge-b", "source" => "b", "target" => "join" },
                                        ],
                                      })
      context.record_node_arrival("join", "a")

      runner.send(:wake_join_if_unblocked!, graph, context, "join", scheduler)

      expect(scheduler).not_to have_received(:enqueue)
    end

    it "re-enqueues a join once all active predecessors have arrived" do
      graph = Missions::FlowGraph.new({
                                        "nodes" => [
                                          { "id" => "a", "type" => "set_variable", "data" => {} },
                                          { "id" => "join", "type" => "output", "data" => {} },
                                        ],
                                        "edges" => [{ "id" => "edge-a", "source" => "a", "target" => "join" }],
                                      })
      context.record_node_arrival("join", "a")

      runner.send(:wake_join_if_unblocked!, graph, context, "join", scheduler)

      expect(scheduler).to have_received(:enqueue).with(
        "join",
        runtime_state: context.snapshot_runtime_state,
      )
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 17. NODE RESULT
  # ══════════════════════════════════════════════════════════════════════

  describe "NodeResult" do
    it "creates a success result" do
      result = Missions::NodeResult.new(status: :success, output: "hello")
      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result).not_to be_skip
      expect(result.output).to eq("hello")
      expect(result.next_port).to eq("default")
    end

    it "creates a failure result" do
      result = Missions::NodeResult.new(status: :failure, output: "error msg")
      expect(result).to be_failure
      expect(result).not_to be_success
    end

    it "creates a skip result" do
      result = Missions::NodeResult.new(status: :skip)
      expect(result).to be_skip
    end

    it "supports custom ports" do
      result = Missions::NodeResult.new(status: :success, next_port: "true")
      expect(result.next_port).to eq("true")
    end

    it "supports variables" do
      result = Missions::NodeResult.new(status: :success, variables: { "x" => 1 })
      expect(result.variables).to eq({ "x" => 1 })
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 18. MISSION NODE PLUGIN REGISTRY
  # ══════════════════════════════════════════════════════════════════════

  describe "MissionNodePlugin registry" do
    it "resolves registered node types" do
      expect(MissionNodePlugin.resolve("input")).to eq(Missions::Nodes::Input)
      expect(MissionNodePlugin.resolve("condition")).to eq(Missions::Nodes::Condition)
      expect(MissionNodePlugin.resolve("output")).to eq(Missions::Nodes::Output)
    end

    it "returns nil for unknown types" do
      expect(MissionNodePlugin.resolve("totally_unknown")).to be_nil
    end

    it "lists all registered types" do
      types = MissionNodePlugin.all_types
      keys = types.pluck(:key)

      expect(keys).to include("input", "llm", "agent", "generate_image", "mission",
                              "condition", "switch", "iterator", "loop",
                              "set_variable", "output",)
    end

    it "groups types by category" do
      by_cat = MissionNodePlugin.types_by_category
      expect(by_cat.keys).to contain_exactly("input_output", "llm", "node", "control")
      expect(by_cat["input_output"].pluck(:key)).to include("input")
      expect(by_cat["llm"].pluck(:key)).to include("llm", "agent", "generate_image")
      expect(by_cat["control"].pluck(:key)).to include("condition", "switch", "iterator", "loop")
      expect(by_cat["input_output"].pluck(:key)).to include("output")
    end

    it "provides metadata for each type" do
      meta = MissionNodePlugin.metadata_for("condition")
      expect(meta[:label]).to eq("Condition")
      expect(meta[:icon]).to eq("fa-solid fa-code-branch")
      expect(meta[:color]).to eq("#f97316")
      expect(meta[:category]).to eq("control")
    end

    it "prevents duplicate registrations of different classes" do
      expect do
        MissionNodePlugin.register(
          "input", "SomeOtherClass",
          label: "X", icon: "x", color: "#000", category: :input_output,
        )
      end.to raise_error(ArgumentError, /already registered/)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 19. INDIVIDUAL NODE TYPES
  # ══════════════════════════════════════════════════════════════════════

  describe "individual node types" do
    let(:mission) { create(:mission) }
    let(:run) { create(:mission_run, mission:) }

    describe "Missions::Nodes::Input" do
      it "passes through input when no fields configured" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "input" => "Hello!" })
        ctx.set_variable("_current_node_data", {})
        result = Missions::Nodes::Input.new.execute(ctx)
        expect(result).to be_success
        expect(result.output).to eq("Hello!")
        expect(result.variables).to eq({ "input" => "Hello!" })
      end
    end

    describe "Missions::Nodes::Condition" do
      it "routes to true port on truthy condition" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "x" => 10 })
        ctx.set_variable("_current_node_data", { "expression" => "x > 5" })
        result = Missions::Nodes::Condition.new.execute(ctx)
        expect(result.next_port).to eq("true")
      end

      it "routes to false port on falsy condition" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "x" => 3 })
        ctx.set_variable("_current_node_data", { "expression" => "x > 5" })
        result = Missions::Nodes::Condition.new.execute(ctx)
        expect(result.next_port).to eq("false")
      end
    end

    describe "Missions::Nodes::Switch" do
      it "routes to matching case" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "status" => 2 })
        ctx.set_variable("_current_node_data", {
                           "expression" => "status",
                           "cases" => { "active" => "1", "pending" => "2", "closed" => "3" },
                         })
        result = Missions::Nodes::Switch.new.execute(ctx)
        expect(result.next_port).to eq("pending")
      end

      it "routes to default when no match" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "status" => 99 })
        ctx.set_variable("_current_node_data", {
                           "expression" => "status",
                           "cases" => { "active" => "1" },
                         })
        result = Missions::Nodes::Switch.new.execute(ctx)
        expect(result.next_port).to eq("default")
      end
    end

    describe "Missions::Nodes::Iterator" do
      it "sets up iteration state for arrays" do
        ctx = Missions::ExecutionContext.new(mission_run: run)
        ctx.set_variable("_current_node_data", { "collection" => '["a","b"]' })
        result = Missions::Nodes::Iterator.new.execute(ctx)
        expect(result.next_port).to eq("loop")
        expect(result.variables["item"]).to eq("a")
        expect(result.variables["total"]).to eq(2)
      end

      it "goes to done port for empty arrays" do
        ctx = Missions::ExecutionContext.new(mission_run: run)
        ctx.set_variable("_current_node_data", { "collection" => "[]" })
        result = Missions::Nodes::Iterator.new.execute(ctx)
        expect(result.next_port).to eq("done")
      end
    end

    describe "Missions::Nodes::Loop" do
      it "continues looping when condition is true" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "x" => 1 })
        ctx.set_variable("_current_node_data", { "condition" => "x = 1", "max_iterations" => "5" })
        ctx.set_variable("_loop_iteration", 0)
        result = Missions::Nodes::Loop.new.execute(ctx)
        expect(result.next_port).to eq("loop")
      end

      it "exits to done when condition is false" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "x" => 0 })
        ctx.set_variable("_current_node_data", { "condition" => "x = 1", "max_iterations" => "5" })
        ctx.set_variable("_loop_iteration", 0)
        result = Missions::Nodes::Loop.new.execute(ctx)
        expect(result.next_port).to eq("done")
      end

      it "exits to done when max iterations reached" do
        ctx = Missions::ExecutionContext.new(mission_run: run)
        ctx.set_variable("_current_node_data", { "max_iterations" => "3" })
        ctx.set_variable("_loop_iteration", 3)
        result = Missions::Nodes::Loop.new.execute(ctx)
        expect(result.next_port).to eq("done")
      end
    end

    describe "Missions::Nodes::SetVariable" do
      it "sets multiple variables from expressions" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "a" => 5 })
        ctx.set_variable("_current_node_data", {
                           "assignments" => { "doubled" => "a * 2", "greeting" => "hello" },
                         })
        result = Missions::Nodes::SetVariable.new.execute(ctx)
        expect(result).to be_success
        expect(ctx.get_variable("doubled")).to eq(10)
        expect(ctx.get_variable("greeting")).to eq("hello")
      end
    end

    describe "Missions::Nodes::Output" do
      it "passes through selected variables" do
        ctx = Missions::ExecutionContext.new(mission_run: run, variables: { "name" => "World", "age" => 30 })
        ctx.set_variable("_current_node_data", { "selected_variables" => ["name"] })
        result = Missions::Nodes::Output.new.execute(ctx)
        expect(result).to be_success
        expect(result.variables).to include({ "name" => "World" })
      end

      it "falls back to the current branch input when no selected variables" do
        ctx = Missions::ExecutionContext.new(mission_run: run)
        ctx.current_input = "fallback value"
        ctx.set_variable("_current_node_data", {})
        result = Missions::Nodes::Output.new.execute(ctx)
        expect(result.output).to include({ "output" => "fallback value" })
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 20. MISSION RUN MODEL
  # ══════════════════════════════════════════════════════════════════════

  describe "MissionRun model" do
    it "validates status inclusion" do
      run = build(:mission_run, status: "invalid")
      expect(run).not_to be_valid
      expect(run.errors[:status]).to be_present
    end

    it "computes duration" do
      run = build(:mission_run,
                  started_at: 5.minutes.ago,
                  completed_at: 2.minutes.ago,)
      expect(run.duration).to be_within(1).of(180)
    end

    it "has proper state predicates", :aggregate_failures do
      expect(build(:mission_run, status: "pending")).to be_pending
      expect(build(:mission_run, status: "running")).to be_running
      expect(build(:mission_run, status: "paused")).to be_paused
      expect(build(:mission_run, status: "completed")).to be_completed
      expect(build(:mission_run, status: "failed")).to be_failed
      expect(build(:mission_run, status: "cancelled")).to be_cancelled
    end

    it "scopes active and finished runs" do
      mission = create(:mission)
      pending_run = create(:mission_run, mission:, status: "pending")
      running_run = create(:mission_run, mission:, status: "running")
      completed_run = create(:mission_run, mission:, status: "completed")

      expect(MissionRun.active).to include(pending_run, running_run)
      expect(MissionRun.active).not_to include(completed_run)
      expect(MissionRun.finished).to include(completed_run)
      expect(MissionRun.finished).not_to include(pending_run, running_run)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 21. ROBUSTNESS & EDGE CASES — MISSING INPUTS
  # ══════════════════════════════════════════════════════════════════════

  describe "missing inputs and empty variables" do
    it "completes a trigger → output flow with no input variables at all" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_completed
      # Output node falls back to branch input, then to the mission input variable.
      expect(run.variables["output"]).to be_nil
    end

    it "tracks edge states without marking each-item completed for empty collections" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "[]")
        f.node("sv", type: "set_variable", assignments: { "seen" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "done" })
        f.edge("t1", "iter", id: "edge-trigger")
        f.edge("iter", "sv", id: "edge-loop", source_handle: "loop")
        f.edge("iter", "o1", id: "edge-done", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.execution_state.dig("edge_states", "edge-trigger")).to eq("completed")
      expect(run.execution_state.dig("edge_states", "edge-loop")).to be_nil
      expect(run.execution_state.dig("edge_states", "edge-done")).to eq("completed")
    end

    it "keeps each-item edges in progress until iteration fully completes" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b"]')
        f.node("sv", type: "set_variable", assignments: { "last_item" => "{{item}}" })
        f.node("o1", type: "output", selected_variables: ["last_item"])
        f.edge("t1", "iter", id: "edge-trigger")
        f.edge("iter", "sv", id: "edge-loop", source_handle: "loop")
        f.edge("iter", "o1", id: "edge-done", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.execution_state.dig("edge_states", "edge-trigger")).to eq("completed")
      expect(run.execution_state.dig("edge_states", "edge-loop")).to eq("completed")
      expect(run.execution_state.dig("edge_states", "edge-done")).to eq("completed")
    end

    it "completes a trigger → set_variable → output flow with no input" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "greeting" => "Hello, World!" })
        f.node("o1", type: "output", selected_variables: ["greeting"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_completed
      expect(run.variables["greeting"]).to eq("Hello, World!")
    end

    it "fails LLM node when connector is not configured" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("llm1", type: "llm")
        f.edge("t1", "llm1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("LLM connector not configured")
    end

    it "fails LLM node when model is not configured" do
      connector = create(:connectors_llm_provider)
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("llm1", type: "llm", connector_id: connector.id.to_s)
        f.edge("t1", "llm1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("LLM model not configured")
    end

    it "fails LLM node when both prompt and input are empty" do
      connector = create(:connectors_llm_provider)
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("llm1", type: "llm", connector_id: connector.id.to_s, model: "gpt-4")
        f.edge("t1", "llm1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_failed
      expect(run.error).to include("no prompt and no input")
    end

    it "fails Agent node when agent_id is not configured" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("a1", type: "agent")
        f.edge("t1", "a1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("Agent not configured")
    end

    it "fails Agent node when agent is not found" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("a1", type: "agent", agent_id: "99999")
        f.edge("t1", "a1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("Agent not found")
    end

    it "fails Agent node when both prompt and input are empty" do
      agent = create(:agent)
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("a1", type: "agent", agent_id: agent.id.to_s)
        f.edge("t1", "a1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_failed
      expect(run.error).to include("no prompt and no input")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 22. CONDITION NODE EDGE CASES
  # ══════════════════════════════════════════════════════════════════════

  describe "condition node edge cases" do
    it "fails when condition expression is missing" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition")
        f.node("yes", type: "set_variable", assignments: { "result" => "YES" })
        f.node("no", type: "set_variable", assignments: { "result" => "NO" })
        f.edge("t1", "cond")
        f.edge("cond", "yes", source_handle: "true")
        f.edge("cond", "no", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("no expression configured")
    end

    it "fails when condition references undefined variables" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition", expression: "undefined_var > 10")
        f.node("yes", type: "set_variable", assignments: { "result" => "YES" })
        f.node("no", type: "set_variable", assignments: { "result" => "NO" })
        f.edge("t1", "cond")
        f.edge("cond", "yes", source_handle: "true")
        f.edge("cond", "no", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("Could not evaluate condition")
    end

    it "evaluates condition with boolean false correctly (not nil)" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "flag" => "0" })
        f.node("cond", type: "condition", expression: "flag > 0")
        f.node("yes", type: "set_variable", assignments: { "result" => "YES" })
        f.node("no", type: "set_variable", assignments: { "result" => "NO" })
        f.edge("t1", "sv")
        f.edge("sv", "cond")
        f.edge("cond", "yes", source_handle: "true")
        f.edge("cond", "no", source_handle: "false")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("NO")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 23. SWITCH NODE EDGE CASES
  # ══════════════════════════════════════════════════════════════════════

  describe "switch node edge cases" do
    it "fails when switch expression is missing" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sw", type: "switch", cases: { "a" => "1" })
        f.node("a", type: "set_variable", assignments: { "result" => "A" })
        f.node("d", type: "set_variable", assignments: { "result" => "D" })
        f.edge("t1", "sw")
        f.edge("sw", "a", source_handle: "a")
        f.edge("sw", "d", source_handle: "default")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("no expression configured")
    end

    it "falls back to string matching when expression evaluates to nil" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "status" => "active" })
        f.node("sw", type: "switch", expression: "status",
                     cases: { "case_active" => "active", "case_pending" => "pending" },)
        f.node("active_out", type: "set_variable", assignments: { "result" => "IS_ACTIVE" })
        f.node("pending_out", type: "set_variable", assignments: { "result" => "IS_PENDING" })
        f.node("default_out", type: "set_variable", assignments: { "result" => "IS_DEFAULT" })
        f.edge("t1", "sv")
        f.edge("sv", "sw")
        f.edge("sw", "active_out", source_handle: "case_active")
        f.edge("sw", "pending_out", source_handle: "case_pending")
        f.edge("sw", "default_out", source_handle: "default")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("IS_ACTIVE")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 24. ITERATOR NODE EDGE CASES
  # ══════════════════════════════════════════════════════════════════════

  describe "iterator node edge cases" do
    it "fails when collection expression is missing" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("no collection configured")
    end

    it "fails when collection variable is not defined" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "my_items")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("not defined")
    end

    it "fails when collection exceeds max size" do
      large_array = (1..1001).to_a.to_json
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: large_array)
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("exceeds maximum")
    end

    it "iterates over a string variable containing a JSON array" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "data")
        f.node("sv", type: "set_variable", assignments: { "count" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "data" => "[1,2,3]" },
      )

      expect(run).to be_completed
      expect(run.execution_state.dig("node_variables", "iterator", "total")).to eq(3)
    end

    it "wraps a single non-array variable value into a one-element array" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "name")
        f.node("sv", type: "set_variable", assignments: { "last" => "{{item}}" })
        f.node("o1", type: "output", selected_variables: ["last"])
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test", "name" => "Alice" },
      )

      expect(run).to be_completed
      expect(run.variables["last"]).to eq("Alice")
    end

    it "handles comma-separated inline expression" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "alpha,beta,gamma")
        f.node("sv", type: "set_variable", assignments: { "count" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
        f.edge("iter", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["results"].size).to eq(3)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 25. LOOP NODE EDGE CASES
  # ══════════════════════════════════════════════════════════════════════

  describe "loop node edge cases" do
    it "exits loop when condition references undefined variables" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", condition: "undefined_var > 0", max_iterations: "100")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      # Should exit the loop (not hang), going to "done"
      expect(run).to be_completed
      expect(run.variables["result"]).to eq("Done")
    end

    it "loops without a condition using max_iterations only" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "3")
        f.node("sv", type: "set_variable", assignments: { "tick" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "Done" })
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
        f.edge("lp", "o1", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 26. SET VARIABLE NODE EDGE CASES
  # ══════════════════════════════════════════════════════════════════════

  describe "set_variable node edge cases" do
    it "handles empty assignments gracefully" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable")
        f.node("o1", type: "output")
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
    end

    it "falls back to string value when expression can't be evaluated" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "msg" => "Hello, World!" })
        f.node("o1", type: "output", selected_variables: ["msg"])
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["msg"]).to eq("Hello, World!")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 27. SUB-MISSION NODE EDGE CASES
  # ══════════════════════════════════════════════════════════════════════

  describe "sub-mission node edge cases" do
    it "fails when mission_id is blank" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sub", type: "mission")
        f.edge("t1", "sub")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("No mission_id configured")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 28. NODE EXECUTION TIMEOUT
  # ══════════════════════════════════════════════════════════════════════

  describe "node execution timeout" do
    it "fails the run when a node exceeds the timeout" do # rubocop:disable RSpec/ExampleLength
      # Stub the timeout to be very short
      stub_const("Missions::Runner::NODE_EXECUTION_TIMEOUT", 0.1)

      # Create a custom node that sleeps
      slow_node = Class.new do
        include MissionNodePlugin

        class << self
          def node_type = "slow_test"
          def node_label = "Slow Test"
          def node_icon = "fa-solid fa-clock"
          def node_color = "#999"
          def node_category = :node
          def node_description = "Slow test node"
        end

        def output_ports
          [{ key: "default", label: "Output" }]
        end

        def execute(_context)
          sleep(1)
          Missions::NodeResult.new(status: :success, output: "done")
        end
      end

      MissionNodePlugin.register(
        "slow_test", slow_node.name,
        label: "Slow Test", icon: "fa-solid fa-clock", color: "#999",
        category: :node, description: "Slow test node",
      )
      allow(MissionNodePlugin).to receive(:resolve).and_call_original
      allow(MissionNodePlugin).to receive(:resolve).with("slow_test").and_return(slow_node)

      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("slow", type: "slow_test")
        f.edge("t1", "slow")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("timed out")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 29. RUNNER RESILIENCE
  # ══════════════════════════════════════════════════════════════════════

  describe "runner resilience" do
    it "marks run as failed even when fail_run raises" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("bad", type: "nonexistent_type")
        f.edge("t1", "bad")
      end

      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)

      # Stub fail_run to raise an error (simulating e.g. a broadcast failure in DebugRunner)
      allow(runner).to receive(:fail_run).and_raise(StandardError, "broadcast broken")

      run = runner.execute(variables: { "input" => "test" })

      # Run should still be marked as failed via the last-resort update_columns
      expect(run.reload.status).to eq("failed")
    end

    it "always records completed_at on failed runs" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("bad", type: "nonexistent_type")
        f.edge("t1", "bad")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.completed_at).to be_present
    end

    it "clears current_node_id and persists a failure node state for unresolved joins" do
      mission = create(:mission, flow_data: unresolved_loop_join_flow)
      run = described_class.new(mission).execute(variables: { "count" => 5 })

      expect(run).to be_failed
      expect(run.current_node_id).to be_nil
      expect(run.execution_state.dig("node_states", "loop", "status")).to eq("failure")
      expect(run.execution_state.dig("node_states", "loop", "error")).to match(/Unresolved multi-input join/)
    end

    it "preserves variables set before a failure" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "saved" => "before_failure" })
        f.node("bad", type: "nonexistent_type")
        f.edge("t1", "sv")
        f.edge("sv", "bad")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.variables["saved"]).to eq("before_failure")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 30. DISCONNECTED AND MALFORMED GRAPHS
  # ══════════════════════════════════════════════════════════════════════

  describe "graph structure edge cases" do
    it "handles a flow with nodes but no edges" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "set_variable", assignments: { "result" => "Isolated" })
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      # Both nodes are roots and both execute (no edges to follow)
      expect(run).to be_completed
    end

    it "handles a single-node flow (trigger only)" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hello" })

      expect(run).to be_completed
      expect(run.variables["input"]).to eq("hello")
    end

    it "handles a leaf node with no outgoing edges gracefully" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "x" => "42" })
        f.edge("t1", "sv")
        # sv has no outgoing edges — execution should just stop cleanly
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["x"]).to eq(42)
    end

    it "handles condition with only one branch connected" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "val" => "10" })
        f.node("cond", type: "condition", expression: "val > 5")
        f.node("yes", type: "set_variable", assignments: { "result" => "YES" })
        # No false branch connected
        f.edge("t1", "sv")
        f.edge("sv", "cond")
        f.edge("cond", "yes", source_handle: "true")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("YES")
    end

    it "completes when condition goes to an unconnected branch" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "val" => "1" })
        f.node("cond", type: "condition", expression: "val > 5")
        f.node("yes", type: "set_variable", assignments: { "final" => "YES" })
        # Only true branch connected, but val=1 will take the false branch
        f.edge("t1", "sv")
        f.edge("sv", "cond")
        f.edge("cond", "yes", source_handle: "true")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      # No output set because false branch has no successor
      expect(run.variables).not_to have_key("final")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # RESUME WITHOUT current_node_id
  # ══════════════════════════════════════════════════════════════════════

  describe "resume without current_node_id" do
    it "falls back to execute_graph when current_node_id is nil" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "set_variable", assignments: { "result" => "Resumed!" })
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "paused",
                                 flow_snapshot: flow, execution_state: {}, variables: {},)
      expect(run.current_node_id).to be_nil

      described_class.new(mission).resume(run)

      expect(run.reload).to be_completed
      expect(run.variables["result"]).to eq("Resumed!")
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # RETRY WITHOUT current_node_id
  # ══════════════════════════════════════════════════════════════════════

  describe "retry_from_failure without current_node_id" do
    it "falls back to execute_graph when current_node_id is nil on retry" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "set_variable", assignments: { "result" => "Retried!" })
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "failed",
                                 flow_snapshot: flow, execution_state: {}, variables: {},)
      expect(run.current_node_id).to be_nil

      described_class.new(mission).retry_from_failure(run)

      expect(run.reload).to be_completed
      expect(run.variables["result"]).to eq("Retried!")
    end
  end

  describe "resume with invalid flow (rescue handler)" do
    it "fails the run when execute_graph raises" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "paused")
      described_class.new(mission).resume(run)
      expect(run.reload).to be_failed
    end
  end

  describe "retry_from_failure with invalid flow (rescue handler)" do
    it "fails the run when execute_graph raises" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "failed")
      described_class.new(mission).retry_from_failure(run)
      expect(run.reload).to be_failed
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # SAFE_SERIALIZE
  # ══════════════════════════════════════════════════════════════════════

  # ══════════════════════════════════════════════════════════════════════
  # BRANCH COVERAGE: EXECUTE_NODE_AND_FOLLOW / ITERATOR / LOOP / FOLLOW_EDGES
  # ══════════════════════════════════════════════════════════════════════

  describe "execute_node_and_follow returns early when run is cancelled" do
    it "skips node execution and completes the run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "done" => "1" })
        f.edge("t1", "sv")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      # Mock cancelled? so execute_node_and_follow returns early for every check
      allow(run).to receive(:cancelled?).and_return(true)

      described_class.new(mission).resume_or_execute(run)

      run.reload
      expect(run).to be_completed
      expect(run.variables).not_to have_key("done")
    end
  end

  describe "execute_node_and_follow raises NodeNotFoundError for unknown node" do
    it "fails the run when resumed from a non-existent current_node_id" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cr", type: "set_variable", assignments: { "result" => "Hello" })
        f.edge("t1", "cr")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run,
                   mission:,
                   status: "paused",
                   flow_snapshot: flow,
                   current_node_id: "non_existent_node_xyz",
                   execution_state: { "variables" => {}, "node_outputs" => {}, "execution_log" => [] },)

      result = described_class.new(mission).resume(run)

      expect(result).to be_failed
      expect(result.error).to include("non_existent_node_xyz")
    end
  end

  describe "iterator break when MAX_TOTAL_EXECUTIONS reached mid-collection" do
    it "stops iteration early and completes the run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b","c"]')
        f.node("sv", type: "set_variable", assignments: { "last" => "{{item}}" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      # With MAX=4: input(+1=1), iterator_initial(+1=2), sv_item0(+1=3), sv_item1(+1=4)
      # → item2 check: break(4>=4) fires
      stub_const("Missions::Runner::MAX_TOTAL_EXECUTIONS", 4)

      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables.fetch("results", []).size).to be < 3
    end
  end

  describe "loop break when MAX_TOTAL_EXECUTIONS reached at top of loop" do
    it "exits the loop and completes the run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "999")
        # No loop body — each iteration only runs the loop handler
        f.edge("t1", "lp")
      end

      mission = create(:mission, flow_data: flow)
      # With MAX=4: input(+1=1), loop_iter1(+1=2), loop_iter2(+1=3),
      # loop_iter3(+1=4) → iter4 check: break(4>=4) fires
      stub_const("Missions::Runner::MAX_TOTAL_EXECUTIONS", 4)

      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
    end
  end

  describe "execute_node_and_follow skips disabled nodes" do
    it "skips the disabled node and follows default edges" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", disabled: true, assignments: { "skipped" => "yes" })
        f.node("sv2", type: "set_variable", assignments: { "reached" => "yes" })
        f.edge("t1", "sv1")
        f.edge("sv1", "sv2")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      run.reload
      expect(run).to be_completed
      expect(run.variables).not_to have_key("skipped")
      expect(run.variables["reached"]).to eq("yes")

      log = run.execution_state["execution_log"]
      skip_entry = log.find { |e| e["node_id"] == "sv1" }
      expect(skip_entry["status"]).to eq("skip")
    end

    it "completes enqueued work items that became runtime-disabled" do
      graph = Missions::FlowGraph.new({ "nodes" => [], "edges" => [] })
      context = Missions::ExecutionContext.new(mission_run: create(:mission_run, mission: create(:mission)))
      context.set_node_state("sv1", :disabled, node_type: "set_variable")
      scheduler = instance_double(Missions::RunnerScheduler, complete_active_work_item: nil)

      result = described_class.new(create(:mission)).send(
        :skip_or_defer_node_execution?,
        create(:mission_run, mission: create(:mission)),
        graph,
        context,
        { id: "sv1", type: "set_variable", data: {} },
        nil,
        scheduler,
      )

      expect(result).to be(true)
      expect(scheduler).to have_received(:complete_active_work_item)
    end
  end

  describe "safe_serialize" do
    let(:runner) { described_class.new(create(:mission)) }

    it "passes through primitive values unchanged" do
      expect(runner.send(:safe_serialize, "hello")).to eq("hello")
      expect(runner.send(:safe_serialize, 42)).to eq(42)
      expect(runner.send(:safe_serialize, true)).to be(true)
      expect(runner.send(:safe_serialize, nil)).to be_nil
    end

    it "recursively serializes arrays" do
      expect(runner.send(:safe_serialize, ["a", 1, nil])).to eq(["a", 1, nil])
    end

    it "recursively serializes hashes" do
      expect(runner.send(:safe_serialize, { "x" => "y", "n" => 3 })).to eq({ "x" => "y", "n" => 3 })
    end

    it "converts non-primitive non-collection values to their string representation" do
      custom = Object.new
      result = runner.send(:safe_serialize, custom)
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  describe "global variables" do
    it "builds an execution context with globals and trigger data" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
      end
      flow["global_variables"] = [
        { "key" => "api_key", "value" => "secret123", "type" => "string" },
      ]

      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      context = runner.send(
        :build_execution_context,
        run,
        variables: { "input" => "test" },
        trigger_data: { "flag" => "enabled" },
      )

      expect(context.get_variable("api_key")).to eq("secret123")
      expect(context.get_variable("input")).to eq("test")
      expect(context.get_variable("_nesting_depth")).to eq(0)
      expect(context.get_variable("_trigger_data")).to eq({ "flag" => "enabled" })
      expect(context.get_variable("flag")).to eq("enabled")
    end

    it "seeds global variables into execution context" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["api_key"])
        f.edge("t1", "o1")
      end
      flow["global_variables"] = [
        { "key" => "api_key", "value" => "secret123", "type" => "string" },
      ]

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["api_key"]).to eq("secret123")
    end

    it "casts number global variables" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition", expression: "threshold > 0.5")
        f.node("sv_yes", type: "set_variable", assignments: { "result" => "above" })
        f.node("sv_no", type: "set_variable", assignments: { "result" => "below" })
        f.edge("t1", "cond")
        f.edge("cond", "sv_yes", source_handle: "true")
        f.edge("cond", "sv_no", source_handle: "false")
      end
      flow["global_variables"] = [
        { "key" => "threshold", "value" => "0.8", "type" => "number" },
      ]

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("above")
    end

    it "casts boolean global variables" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["flag"])
        f.edge("t1", "o1")
      end
      flow["global_variables"] = [
        { "key" => "flag", "value" => "true", "type" => "boolean" },
      ]

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["flag"]).to be true
    end

    it "casts integer global variables" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["count"])
        f.edge("t1", "o1")
      end
      flow["global_variables"] = [
        { "key" => "count", "value" => "42", "type" => "number" },
      ]

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["count"]).to eq(42)
    end

    it "allows trigger_data to override global variables" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["api_key"])
        f.edge("t1", "o1")
      end
      flow["global_variables"] = [
        { "key" => "api_key", "value" => "default", "type" => "string" },
      ]

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(
        variables: { "input" => "test" },
        trigger_data: { "api_key" => "override" },
      )

      expect(run).to be_completed
      expect(run.variables["api_key"]).to eq("override")
    end
  end

  describe "finalize_run when run is not active" do
    it "does not update a cancelled run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      # Cancel the run mid-execution by stubbing
      call_count = 0
      original_update = run.method(:update!)
      allow(run).to receive(:update!) do |**attrs|
        call_count += 1
        # Cancel the run after the first update (status: running)
        if call_count == 1
          original_update.call(**attrs)
          run.update_columns(status: :cancelled, completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        else
          original_update.call(**attrs)
        end
      end
      allow(run).to receive(:reload).and_call_original

      described_class.new(mission).resume_or_execute(run)
      run.reload
      expect(run).to be_cancelled
    end

    it "persists execution state for a cancelled run" do
      mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      runner = described_class.new(mission)
      run = create(:mission_run, mission:, status: "cancelled", flow_snapshot: mission.flow_data)
      context = instance_double(Missions::ExecutionContext, variables: { "saved" => true }, to_h: { "log" => [] })

      runner.send(:finalize_run, run, context)

      run.reload
      expect(run.variables).to eq({ "saved" => true })
      expect(run.execution_state).to eq({ "log" => [] })
      expect(run.current_node_id).to be_nil
    end

    it "does not update non-cancelled inactive runs" do
      mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      runner = described_class.new(mission)
      run = create(:mission_run, mission:, status: "failed", flow_snapshot: mission.flow_data)
      context = instance_double(Missions::ExecutionContext, variables: { "saved" => true }, to_h: { "log" => [] })

      allow(run).to receive(:update!)
      runner.send(:finalize_run, run, context)

      expect(run).not_to have_received(:update!)
    end
  end

  describe "multi_port_node?" do
    it "returns false when the node type is not registered" do
      runner = described_class.new(create(:mission))

      expect(runner.send(:multi_port_node?, "missing_type")).to be(false)
    end
  end

  describe "fail_run itself raises" do
    it "marks the run as failed via update_columns when fail_run raises" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition") # no expression → node fails
        f.edge("t1", "cond")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      # Make fail_run's update! raise to exercise the rescue inner branch
      fail_count = 0
      original_update = run.method(:update!)
      allow(run).to receive(:update!) do |**attrs|
        if attrs[:status]&.to_s == "failed"
          fail_count += 1
          raise StandardError, "DB write error" if fail_count == 1
        end
        original_update.call(**attrs)
      end
      allow(run).to receive(:reload).and_call_original
      allow(Rails.logger).to receive(:error)

      described_class.new(mission).resume_or_execute(run)
      run.reload
      expect(run.status).to eq("failed")
      expect(Rails.logger).to have_received(:error).with(/fail_run itself raised/)
    end

    it "skips update_columns when fail_run raises after the run is already inactive" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition")
        f.edge("t1", "cond")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)
      runner = described_class.new(mission)

      allow(runner).to receive(:fail_run).and_raise(StandardError, "broadcast broken")
      allow(run).to receive(:active?).and_return(false)
      allow(run).to receive(:update_columns)
      allow(Rails.logger).to receive(:error)

      runner.resume_or_execute(run)

      expect(run).not_to have_received(:update_columns)
      expect(Rails.logger).to have_received(:error).with(/fail_run itself raised/)
    end
  end

  describe "iterator cancelled mid-collection" do
    it "stops iterating when run is cancelled" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b","c","d"]')
        f.node("sv", type: "set_variable", assignments: { "x" => "{{item}}" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      # Cancel after first iteration reload
      reload_count = 0
      original_reload = run.method(:reload)
      allow(run).to receive(:reload) do
        result = original_reload.call
        reload_count += 1
        # After several reloads, cancel the run
        if reload_count >= 6
          run.update_columns(status: :cancelled, completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end
        result
      end

      described_class.new(mission).resume_or_execute(run)
      run.reload
      # Should be cancelled, not completed
      expect(run).to be_cancelled
    end
  end

  describe "loop cancelled mid-iteration" do
    it "stops looping when run is cancelled" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "100")
        f.node("sv", type: "set_variable", assignments: { "tick" => "{{iteration}}" })
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      reload_count = 0
      original_reload = run.method(:reload)
      allow(run).to receive(:reload) do
        result = original_reload.call
        reload_count += 1
        if reload_count >= 5
          run.update_columns(status: :cancelled, completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end
        result
      end

      described_class.new(mission).resume_or_execute(run)
      run.reload
      expect(run).to be_cancelled
    end
  end

  describe "resolve_outgoing_edges fallback" do
    it "falls back to default port when specific port has no edges" do
      runner = described_class.new(create(:mission))
      graph = instance_double(Missions::FlowGraph)
      allow(graph).to receive(:outgoing_edges).with("n1", port: "custom").and_return([])
      allow(graph).to receive(:outgoing_edges).with("n1", port: "default").and_return([{ "id" => "e1" }])

      edges = runner.send(:resolve_outgoing_edges, graph, "n1", "custom")
      expect(edges).to eq([{ "id" => "e1" }])
    end

    it "falls back to unfiltered edges when default also empty" do
      runner = described_class.new(create(:mission))
      graph = instance_double(Missions::FlowGraph)
      allow(graph).to receive(:outgoing_edges).with("n1", port: "custom").and_return([])
      allow(graph).to receive(:outgoing_edges).with("n1", port: "default").and_return([])
      allow(graph).to receive(:outgoing_edges).with("n1").and_return([{ "id" => "e2" }])

      edges = runner.send(:resolve_outgoing_edges, graph, "n1", "custom")
      expect(edges).to eq([{ "id" => "e2" }])
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # STRICT PORT ROUTING FOR MULTI-PORT NODES
  # ══════════════════════════════════════════════════════════════════════

  describe "strict port routing for multi-port nodes" do
    before do
      MissionNodePlugin.register(
        "http_request", "Missions::Nodes::HttpRequest",
        label: "HTTP Request", icon: "fa-solid fa-globe", color: "#0284c7",
        category: :node, description: "Makes HTTP requests",
      )
      MissionNodePlugin.register(
        "filter", "Missions::Nodes::Filter",
        label: "Filter", icon: "fa-solid fa-filter", color: "#f59e0b",
        category: :node, description: "Filters collections",
      )
    end

    def stub_http_response(status:, body: "") # rubocop:disable Metrics/AbcSize
      http = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:"use_ssl=")
      allow(http).to receive(:"open_timeout=")
      allow(http).to receive(:"read_timeout=")
      resp = double("Net::HTTPResponse", code: status.to_s, body:) # rubocop:disable RSpec/VerifiedDoubles
      allow(resp).to receive(:[]).with("content-type").and_return(nil)
      allow(resp).to receive(:each_header).and_return({}.each)
      allow(http).to receive(:request).and_return(resp)
    end

    def execute_flow(flow)
      mission = create(:mission, flow_data: flow)
      described_class.new(mission).execute(variables: { "input" => "test" })
    end

    def build_toplevel_http_flow
      MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("req1", type: "http_request",
                       url: "https://api.example.com/data", method: "GET",)
        f.node("ok", type: "set_variable", assignments: { "success_ran" => "yes" })
        f.node("err", type: "set_variable", assignments: { "error_ran" => "yes" })
        f.edge("t1", "req1")
        f.edge("req1", "ok", source_handle: "success")
        f.edge("req1", "err", source_handle: "error")
      end
    end

    context "with HTTP request routing" do
      it "follows only the success branch on 2xx response" do
        stub_http_response(status: 200, body: '{"ok":true}')
        run = execute_flow(build_toplevel_http_flow)

        expect(run).to be_completed
        expect(run.variables["success_ran"]).to eq("yes")
        expect(run.variables["error_ran"]).to be_nil
      end

      it "follows only the error branch on non-2xx response" do
        stub_http_response(status: 404, body: "Not Found")
        run = execute_flow(build_toplevel_http_flow)

        expect(run).to be_completed
        expect(run.variables["success_ran"]).to be_nil
        expect(run.variables["error_ran"]).to eq("yes")
      end

      it "does not fall back to all edges when success port has no edges" do
        stub_http_response(status: 200, body: '{"ok":true}')
        flow = MissionFlowBuilder.build do |f|
          f.node("t1", type: "input")
          f.node("req1", type: "http_request",
                         url: "https://api.example.com/data", method: "GET",)
          f.node("err", type: "set_variable", assignments: { "error_ran" => "yes" })
          f.edge("t1", "req1")
          f.edge("req1", "err", source_handle: "error")
        end

        run = execute_flow(flow)
        expect(run).to be_completed
        expect(run.variables["error_ran"]).to be_nil
      end
    end

    context "with filter node strict routing" do
      it "follows only the match branch when items match" do
        flow = MissionFlowBuilder.build do |f|
          f.node("t1", type: "input")
          f.node("sv", type: "set_variable", assignments: { "items" => "[1, 2, 3]" })
          f.node("f1", type: "filter", collection: "{{items}}", expression: "item > 1")
          f.node("m", type: "set_variable", assignments: { "match_ran" => "yes" })
          f.node("nm", type: "set_variable", assignments: { "no_match_ran" => "yes" })
          f.edge("t1", "sv")
          f.edge("sv", "f1")
          f.edge("f1", "m", source_handle: "match")
          f.edge("f1", "nm", source_handle: "no_match")
        end

        run = execute_flow(flow)
        expect(run).to be_completed
        expect(run.variables["match_ran"]).to eq("yes")
        expect(run.variables["no_match_ran"]).to be_nil
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # 10. OUTPUT NODE EARLY TERMINATION
  # ══════════════════════════════════════════════════════════════════════

  describe "output node early termination" do
    before do
      MissionNodePlugin.register(
        "text_template", "Missions::Nodes::TextTemplate",
        label: "Text Template", icon: "fa-solid fa-file-lines", color: "#7c3aed",
        category: :node, description: "Composes text",
      )
    end

    def execute_flow(flow, variables: { "input" => "test" })
      mission = create(:mission, flow_data: flow)
      described_class.new(mission).execute(variables:)
    end

    it "completes the run when the output node is reached in a simple flow" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "greeting" => "hello" })
        f.node("o1", type: "output", selected_variables: ["greeting"])
        f.edge("t1", "sv1")
        f.edge("sv1", "o1")
      end

      run = execute_flow(flow)
      expect(run).to be_completed
      expect(run.variables["greeting"]).to eq("hello")
    end

    it "stops execution after output node — downstream nodes do not run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output", selected_variables: ["input"])
        f.node("sv_after", type: "set_variable", assignments: { "should_not_run" => "true" })
        f.edge("t1", "o1")
        # Output has no outgoing edges (terminal), but even if somehow
        # connected the workflow should have already stopped.
      end

      run = execute_flow(flow, variables: { "input" => "original" })
      expect(run).to be_completed
      expect(run.variables["input"]).to eq("original")
      expect(run.variables["should_not_run"]).to be_nil
    end

    it "terminates workflow when output node is deeper in the chain" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "step1" => "first" })
        f.node("sv2", type: "set_variable", assignments: { "step2" => "second" })
        f.node("o1", type: "output", selected_variables: ["step1", "step2"])
        f.node("sv_after", type: "set_variable",
                           assignments: { "should_not_run" => "true" },)
        f.edge("t1", "sv1")
        f.edge("sv1", "sv2")
        f.edge("sv2", "o1")
        f.edge("o1", "sv_after")
      end

      run = execute_flow(flow)
      expect(run).to be_completed
      expect(run.variables["step1"]).to eq("first")
      expect(run.variables["step2"]).to eq("second")
      expect(run.variables["should_not_run"]).to be_nil
    end

    it "uses the first output node when a condition branches to two outputs" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv_val", type: "set_variable", assignments: { "x" => "42" })
        f.node("cond", type: "condition", expression: "x == 42")
        f.node("o_true", type: "output", selected_variables: ["x"])
        f.node("o_false", type: "output", selected_variables: ["x"])
        f.edge("t1", "sv_val")
        f.edge("sv_val", "cond")
        f.edge("cond", "o_true", source_handle: "true")
        f.edge("cond", "o_false", source_handle: "false")
      end

      run = execute_flow(flow)
      expect(run).to be_completed
      expect(run.variables["x"]).to eq(42)
    end

    it "captures selected variables from the output node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "a" => "1", "b" => "2", "c" => "3" })
        f.node("o1", type: "output", selected_variables: ["a", "c"])
        f.edge("t1", "sv1")
        f.edge("sv1", "o1")
      end

      run = execute_flow(flow)
      expect(run).to be_completed
      expect(run.variables["a"]).to eq(1)
      expect(run.variables["c"]).to eq(3)
    end

    it "falls back to the current branch input when no variables are selected" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "msg" => "fallback_value" })
        f.node("o1", type: "output")
        f.edge("t1", "sv1")
        f.edge("sv1", "o1")
      end

      run = execute_flow(flow)
      expect(run).to be_completed
      expect(run.variables["output"]).to be_present
    end

    it "terminates workflow when output is inside an iterator loop body" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv_list", type: "set_variable",
                          assignments: { "items" => "[1, 2, 3]" },)
        f.node("iter", type: "iterator", collection: "{{items}}")
        f.node("o1", type: "output", selected_variables: ["item"])
        f.node("sv_done", type: "set_variable",
                          assignments: { "should_not_run" => "true" },)
        f.edge("t1", "sv_list")
        f.edge("sv_list", "iter")
        f.edge("iter", "o1", source_handle: "loop")
        f.edge("iter", "sv_done", source_handle: "done")
      end

      run = execute_flow(flow)
      expect(run).to be_completed
      # First iteration item is captured
      expect(run.variables["item"]).to eq(1)
      # Done branch never executed
      expect(run.variables["should_not_run"]).to be_nil
    end

    it "terminates workflow when output is inside a loop body" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv_init", type: "set_variable", assignments: { "counter" => "0" })
        f.node("lp", type: "loop", expression: "counter < 5", max_iterations: 10)
        f.node("sv_inc", type: "set_variable", assignments: { "counter" => "{{counter + 1}}" })
        f.node("o1", type: "output", selected_variables: ["counter"])
        f.node("sv_done", type: "set_variable",
                          assignments: { "should_not_run" => "true" },)
        f.edge("t1", "sv_init")
        f.edge("sv_init", "lp")
        f.edge("lp", "sv_inc", source_handle: "loop")
        f.edge("sv_inc", "o1")
        f.edge("lp", "sv_done", source_handle: "done")
      end

      run = execute_flow(flow)
      expect(run).to be_completed
      # Output was reached during first loop iteration — counter was incremented once
      expect(run.variables["counter"]).to be_present
      # Done branch never executed
      expect(run.variables["should_not_run"]).to be_nil
    end

    it "records the output node execution in the log" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      run = execute_flow(flow)
      expect(run).to be_completed

      output_execution = run.node_executions.find { |e| e.node_type == "output" }
      expect(output_execution).to be_present
      expect(output_execution.status).to eq(:success)
    end
  end
end
