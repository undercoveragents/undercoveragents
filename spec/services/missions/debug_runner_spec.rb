# frozen_string_literal: true

require "rails_helper"
require "support/mission_flow_builder"

RSpec.describe Missions::DebugRunner do
  before do
    allow_any_instance_of(described_class).to receive(:sleep) # rubocop:disable RSpec/AnyInstance

    MissionNodePlugin.reset!

    MissionNodePlugin.register(
      "input", "Missions::Nodes::Input",
      label: "Input", icon: "fa-solid fa-right-to-bracket", color: "#10b981",
      category: :input_output, description: "Receives input fields",
    )
    MissionNodePlugin.register(
      "output", "Missions::Nodes::Output",
      label: "Output", icon: "fa-solid fa-arrow-right-from-bracket", color: "#ec4899",
      category: :input_output, description: "Selects variables to output",
    )
    MissionNodePlugin.register(
      "set_variable", "Missions::Nodes::SetVariable",
      label: "Set Variable", icon: "fa-solid fa-equals", color: "#84cc16",
      category: :control, description: "Sets variables",
    )
    MissionNodePlugin.register(
      "condition", "Missions::Nodes::Condition",
      label: "Condition", icon: "fa-solid fa-code-branch", color: "#f97316",
      category: :control, description: "Branches based on condition",
    )
    MissionNodePlugin.register(
      "iterator", "Missions::Nodes::Iterator",
      label: "Iterator", icon: "fa-solid fa-repeat", color: "#0ea5e9",
      category: :control, description: "Iterates over a collection",
    )
    MissionNodePlugin.register(
      "loop", "Missions::Nodes::Loop",
      label: "Loop", icon: "fa-solid fa-arrows-rotate", color: "#14b8a6",
      category: :control, description: "Repeats while a condition is met",
    )
  end

  after { MissionNodePlugin.restore_defaults! }

  describe "broadcast resilience" do
    it "completes the run even when broadcasts fail" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "set_variable", assignments: { "result" => "Hello" })
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)

      # Make all broadcasts raise
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(StandardError, "broadcast failed")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "broadcast failed")
      allow(Rails.logger).to receive(:error)

      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(run.variables["result"]).to eq("Hello")
    end

    it "completes the run when a broadcast raises PG::InvalidParameterValue" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "set_variable", assignments: { "result" => "Hello" })
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)

      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        .and_raise(PG::InvalidParameterValue, "payload string too long")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        .and_raise(PG::InvalidParameterValue, "payload string too long")
      allow(Rails.logger).to receive(:warn)

      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "test" })

      expect(run).to be_completed
      expect(Rails.logger).to have_received(:warn).with(/Broadcast skipped/).at_least(:once)
    end

    it "broadcasts failure status when a node fails" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition")
        f.edge("t1", "cond")
      end

      mission = create(:mission, flow_data: flow)

      broadcasts = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*_args, **kwargs|
        broadcasts << kwargs[:locals] if kwargs[:target] == "mission-run-status"
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "test" })

      expect(run).to be_failed

      # The last run-status broadcast should be "failed"
      status_broadcasts = broadcasts.select { |b| b[:run_status].present? }
      expect(status_broadcasts.last[:run_status]).to eq("failed")
    end
  end

  describe "node state broadcasts" do
    it "broadcasts running and completed states for each node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "output")
        f.edge("t1", "sv")
        f.edge("sv", "o1")
      end

      mission = create(:mission, flow_data: flow)

      node_events = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_events << kwargs[:html] if kwargs[:target] == "mission-node-events"
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "test" })

      expect(run).to be_completed

      # Each node should have a "running" event followed by a completion event
      running_events = node_events.select { |e| e.include?('data-state="running"') }
      expect(running_events.size).to eq(3) # t1, sv, o1

      success_events = node_events.select { |e| e.include?('data-state="success"') }
      expect(success_events.size).to eq(3) # t1, sv, o1
    end
  end

  describe "runtime branch pruning broadcasts" do
    let(:node_events) { [] }
    let(:edge_events) { [] }

    def build_pruned_branch_flow
      MissionFlowBuilder.build do |f|
        pruning_broadcast_nodes.each { |id, type, data| f.node(id, type:, **data) }
        pruning_broadcast_edges.each { |source, target, options| f.edge(source, target, **options) }
      end
    end

    def pruning_broadcast_nodes
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

    def pruning_broadcast_edges
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

    def expect_disabled_edge_events(*edge_ids)
      disabled_edge_events = edge_events.select { |html| html.include?('data-edge-state="disabled"') }

      expect(disabled_edge_events).not_to be_empty
      edge_ids.each do |edge_id|
        expect(disabled_edge_events.join(" ")).to include(edge_id)
      end
    end

    def expect_disabled_node_events(*node_ids)
      disabled_node_events = node_events.select { |html| html.include?('data-state="disabled"') }

      node_ids.each do |node_id|
        expect(disabled_node_events.join(" ")).to include(node_id)
      end
    end

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_events << kwargs[:html] if kwargs[:html]
        edge_events << kwargs[:html] if kwargs[:html]&.include?("data-edge-id")
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "broadcasts disabled edges and disabled nodes for pruned branches" do
      mission = create(:mission, flow_data: build_pruned_branch_flow)
      run = described_class.new(mission).execute(variables: {})

      expect(run).to be_completed
      expect_disabled_edge_events(
        "edge-cond_one-false",
        "edge-false_bridge-join_one",
        "edge-cond_two-false",
        "edge-false_two-join_two",
      )
      expect_disabled_node_events("false_bridge", "false_two")
    end
  end

  describe "execute_single_node error propagation" do
    let(:node_events) { [] }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_events << kwargs[:html] if kwargs[:html]
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "broadcasts failure state and re-raises Missions::ExecutionError" do
      stub_const("BoomExecutionErrorNode", Class.new do
        def execute(_context) = raise Missions::ExecutionError, "deliberate ExecutionError"

        def output_ports = []
      end,)
      MissionNodePlugin.register("boom_exec", "BoomExecutionErrorNode",
                                 label: "Boom", icon: "x", color: "#000", category: :node,)
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("b1", type: "boom_exec")
        f.edge("t1", "b1")
      end
      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })
      expect(run).to be_failed
      expect(node_events.select { |e| e.include?('data-state="failure"') }).not_to be_empty
    end

    it "broadcasts failure state and re-raises a plain StandardError" do
      stub_const("BoomStandardErrorNode", Class.new do
        def execute(_context) = raise StandardError, "deliberate StandardError"

        def output_ports = []
      end,)
      MissionNodePlugin.register("boom_std", "BoomStandardErrorNode",
                                 label: "Boom Std", icon: "x", color: "#000", category: :node,)
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("b1", type: "boom_std")
        f.edge("t1", "b1")
      end
      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })
      expect(run).to be_failed
      expect(node_events.select { |e| e.include?('data-state="failure"') }).not_to be_empty
    end
  end

  describe "fail_run broadcast failure" do
    it "still marks the run as failed when fail_run cannot broadcast the failed status" do
      # A condition without expression will cause a node failure,
      # triggering fail_run. All broadcasts are forced to raise so that
      # safely_broadcast's error-handling branch is exercised.
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition") # no expression → node fails
        f.edge("t1", "cond")
      end
      mission = create(:mission, flow_data: flow)

      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(StandardError, "broadcast error")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "broadcast error")
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)

      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "test" })

      expect(run).to be_failed
    end
  end

  describe "execute_iterator_flow broadcasts" do
    let(:node_events) { [] }
    let(:edge_events) { [] }
    let(:timeline_entries) { [] }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_events << kwargs[:html] if kwargs[:html]
        edge_events << kwargs[:html] if kwargs[:html]&.include?("data-edge-id")
        timeline_entries << kwargs[:locals][:entry] if kwargs[:target] == "mission-timeline-entries" && kwargs[:locals]
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "broadcasts running then success states for the iterator node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b"]')
        f.node("sv", type: "set_variable", assignments: { "x" => "{{item}}" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "hi" })

      expect(run).to be_completed
      running = node_events.select { |e| e.include?('"running"') && e.include?("iter") }
      expect(running).not_to be_empty
      success = node_events.select { |e| e.include?('"success"') && e.include?("iter") }
      expect(success).not_to be_empty
      expect(runner.instance_variable_get(:@running_node_ids)).not_to include("iter")
    end

    it "broadcasts a timeline entry for the iterator node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b"]')
        f.node("sv", type: "set_variable", assignments: { "x" => "{{item}}" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_completed
      iter_entries = timeline_entries.select { |e| e[:node_id] == "iter" }
      expect(iter_entries).not_to be_empty
      expect(iter_entries.last[:node_type]).to eq("iterator")
      expect(iter_entries.last[:status]).to eq("success")
      expect(iter_entries.last[:duration_ms]).to be_a(Numeric)
    end

    it "broadcasts failure state when a node in the iterator body raises" do
      # A condition node with no expression returns :failure, causing execute_single_node
      # to raise ExecutionError, which propagates out of the base execute_iterator_flow
      # and is caught by debug_runner's rescue StandardError block.
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a"]')
        f.node("cond", type: "condition") # no expression → fails
        f.edge("t1", "iter")
        f.edge("iter", "cond", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_failed
      failure_events = node_events.select { |e| e.include?('"failure"') && e.include?("iter") }
      expect(failure_events).not_to be_empty
    end

    it "broadcasts completed count for iterated nodes" do # rubocop:disable RSpec/MultipleExpectations
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b","c"]')
        f.node("sv", type: "set_variable", assignments: { "x" => "{{item}}" })
        f.edge("t1", "iter")
        f.edge("iter", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_completed

      # The set_variable node runs 3 times; each completion event should carry the count
      sv_success = node_events.select { |e| e.include?('data-state="success"') && e.include?('"sv"') }
      expect(sv_success.size).to eq(3)
      expect(sv_success.last).to include('data-completed-count="3"')

      # Running events should carry previous completion count
      sv_running = node_events.select { |e| e.include?('data-state="running"') && e.include?('"sv"') }
      expect(sv_running.size).to eq(3)
      expect(sv_running.first).not_to include("data-completed-count") # 0 → not included
      expect(sv_running.last).to include('data-completed-count="2"')
    end

    it "does not broadcast each-item completion for an empty iterator" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: "[]")
        f.node("sv", type: "set_variable", assignments: { "x" => "1" })
        f.node("o1", type: "set_variable", assignments: { "result" => "done" })
        f.edge("t1", "iter", id: "edge-trigger")
        f.edge("iter", "sv", id: "edge-loop", source_handle: "loop")
        f.edge("iter", "o1", id: "edge-done", source_handle: "done")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_completed
      loop_events = edge_events.select { |html| html.include?("edge-loop") }
      loop_execution_events = loop_events.reject { |html| html.include?('data-edge-state="reset"') }
      expect(loop_execution_events).to be_empty
      done_events = edge_events.select { |html| html.include?("edge-done") }
      expect(done_events).not_to be_empty
      expect(done_events.last).to include('data-edge-state="completed"')
    end

    it "broadcasts each-item edges as in progress before they complete" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a","b"]')
        f.node("sv", type: "set_variable", assignments: { "x" => "{{item}}" })
        f.edge("t1", "iter", id: "edge-trigger")
        f.edge("iter", "sv", id: "edge-loop", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_completed
      loop_events = edge_events.select { |html| html.include?("edge-loop") }
      loop_events = loop_events.reject { |html| html.include?('data-edge-state="reset"') }
      expect(loop_events).not_to be_empty
      expect(loop_events.first).to include('data-edge-state="in_progress"')
      expect(loop_events.last).to include('data-edge-state="completed"')
    end

    it "handles OutputReached raised inside the iterator body" do
      # An output node on the loop port terminates the workflow via OutputReached
      # during iterator execution. The debug runner should remove the iterator
      # from @running_node_ids (lines 85-86) and re-raise so execute_run can
      # finalize the run. Also covers broadcast_remaining_cancelled (257-260)
      # and broadcast_cancelled_timeline_entry / resolve_node_type (333+, 363+).
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("iter", type: "iterator", collection: '["a"]')
        f.node("o1", type: "output")
        f.edge("t1", "iter")
        f.edge("iter", "o1", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      # Run completes because execute_run catches OutputReached and calls finalize_run
      expect(run).to be_completed
    end
  end

  describe "execute_loop_flow broadcasts" do
    let(:node_events) { [] }
    let(:timeline_entries) { [] }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_events << kwargs[:html] if kwargs[:html]
        timeline_entries << kwargs[:locals][:entry] if kwargs[:target] == "mission-timeline-entries" && kwargs[:locals]
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "broadcasts running then success states for the loop node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "2")
        f.node("sv", type: "set_variable", assignments: { "tick" => "{{iteration}}" })
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)
      run = runner.execute(variables: { "input" => "hi" })

      expect(run).to be_completed
      running = node_events.select { |e| e.include?('"running"') && e.include?("lp") }
      expect(running).not_to be_empty
      success = node_events.select { |e| e.include?('"success"') && e.include?("lp") }
      expect(success).not_to be_empty
      expect(runner.instance_variable_get(:@running_node_ids)).not_to include("lp")
    end

    it "broadcasts a timeline entry for the loop node" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "2")
        f.node("sv", type: "set_variable", assignments: { "tick" => "{{iteration}}" })
        f.edge("t1", "lp")
        f.edge("lp", "sv", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_completed
      loop_entries = timeline_entries.select { |e| e[:node_id] == "lp" }
      expect(loop_entries).not_to be_empty
      expect(loop_entries.last[:node_type]).to eq("loop")
      expect(loop_entries.last[:status]).to eq("success")
      expect(loop_entries.last[:duration_ms]).to be_a(Numeric)
    end

    it "broadcasts failure state when a node in the loop body raises" do
      # A condition node with no expression returns :failure, causing execute_single_node
      # to raise ExecutionError, which propagates out of the base execute_loop_flow
      # and is caught by debug_runner's rescue StandardError block.
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "3")
        f.node("cond", type: "condition") # no expression → fails
        f.edge("t1", "lp")
        f.edge("lp", "cond", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_failed
      failure_events = node_events.select { |e| e.include?('"failure"') && e.include?("lp") }
      expect(failure_events).not_to be_empty
    end

    it "handles OutputReached raised inside the loop body" do
      # An output node on the loop port terminates the workflow via OutputReached
      # during loop execution. The debug runner should remove the loop node
      # from @running_node_ids and re-raise so execute_run can finalise the run.
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("lp", type: "loop", max_iterations: "3")
        f.node("o1", type: "output")
        f.edge("t1", "lp")
        f.edge("lp", "o1", source_handle: "loop")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      # Run completes because execute_run catches OutputReached and calls finalize_run
      expect(run).to be_completed
    end
  end

  describe "safe_output" do
    let(:runner) { described_class.new(create(:mission)) }

    it "truncates long strings" do
      long_str = "x" * 3000
      result = runner.send(:safe_output, long_str)
      expect(result.length).to be <= Missions::DebugRunner::BROADCAST_STRING_LIMIT + 15
      expect(result).to include("(truncated)")
    end

    it "processes arrays recursively" do
      result = runner.send(:safe_output, [1, "hello", nil])
      expect(result).to eq([1, "hello", nil])
    end

    it "limits array size with a truncation notice" do
      result = runner.send(:safe_output, (1..15).to_a)

      expect(result.size).to eq(Missions::DebugRunner::BROADCAST_ARRAY_LIMIT + 1)
      expect(result.last).to eq("... (5 more items)")
    end

    it "processes hash values recursively" do
      result = runner.send(:safe_output, { "key" => "value", "num" => 42 })
      expect(result).to eq({ "key" => "value", "num" => 42 })
    end

    it "limits hash size with a truncation notice" do
      large_hash = (1..15).index_by { |index| "key_#{index}" }

      result = runner.send(:safe_output, large_hash)

      expect(result[Missions::DebugRunner::BROADCAST_HASH_NOTICE_KEY]).to eq("3 more keys")
      expect(result.keys.size).to eq(Missions::DebugRunner::BROADCAST_HASH_LIMIT + 1)
    end

    it "preserves file metadata needed for debug download links" do
      result = runner.send(:safe_output, {
                             "filename" => "report.txt",
                             "blob_id" => 123,
                             "content_type" => "text/plain",
                             "byte_size" => 42,
                             "url" => "https://example.test/#{"x" * 2000}",
                           })

      expect(result).to eq({
                             "filename" => "report.txt",
                             "blob_id" => 123,
                             "content_type" => "text/plain",
                             "byte_size" => 42,
                           })
    end

    it "omits blank optional file metadata from debug download payloads" do
      result = runner.send(:safe_output, {
                             "filename" => "report.txt",
                             "blob_id" => 123,
                             "content_type" => "",
                             "byte_size" => nil,
                           })

      expect(result).to eq({
                             "filename" => "report.txt",
                             "blob_id" => 123,
                           })
    end

    it "cuts off deeply nested structures" do
      nested = { "a" => { "b" => { "c" => { "d" => { "e" => "value" } } } } }

      result = runner.send(:safe_output, nested)

      expect(result.dig("a", "b", "c", "d")).to eq(Missions::DebugRunner::BROADCAST_NESTED_NOTICE)
    end

    it "converts unknown types to string" do
      custom = Object.new
      expect(runner.send(:safe_output, custom)).to be_a(String)
    end

    it "does not truncate data URIs" do
      data_uri = "data:image/png;base64,#{"a" * 5000}"

      expect(runner.send(:safe_output, data_uri)).to eq(data_uri)
    end
  end

  describe "safely_broadcast" do
    it "logs and swallows StandardError exceptions" do
      runner = described_class.new(create(:mission))
      allow(Rails.logger).to receive(:error)

      expect do
        runner.send(:safely_broadcast) { raise StandardError, "boom" }
      end.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/Broadcast error: StandardError — boom/)
    end

    it "logs StandardError exceptions even when the backtrace is missing" do
      runner = described_class.new(create(:mission))
      allow(Rails.logger).to receive(:error)
      exception_class = Class.new(StandardError) do
        def backtrace = nil
      end

      expect do
        runner.send(:safely_broadcast) { raise exception_class, "boom" }
      end.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/Broadcast error: .* — boom \(\)/)
    end
  end

  describe "global variable validation" do
    it "raises ExecutionError when global variables have blank values" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end
      flow["global_variables"] = [
        { "key" => "api_key", "value" => "", "type" => "string" },
        { "key" => "ok_var", "value" => "has_value", "type" => "string" },
        { "key" => "empty_too", "value" => "", "type" => "number" },
      ]

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_failed
      expect(run.error).to include("api_key")
      expect(run.error).to include("empty_too")
      expect(run.error).not_to include("ok_var")
    end

    it "allows execution when all global variables have values" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end
      flow["global_variables"] = [
        { "key" => "api_key", "value" => "secret", "type" => "string" },
      ]

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
    end
  end

  describe "finalize_run when not completed" do
    it "does not broadcast completed status when run is failed" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond", type: "condition") # no expression → fails
        f.edge("t1", "cond")
      end

      mission = create(:mission, flow_data: flow)
      status_broadcasts = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*_args, **kwargs|
        status_broadcasts << kwargs[:locals][:run_status] if kwargs[:target] == "mission-run-status"
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

      run = described_class.new(mission).execute(variables: { "input" => "test" })
      expect(run).to be_failed
      # The "completed" status should NOT have been broadcast
      expect(status_broadcasts).not_to include("completed")
    end
  end

  describe "broadcast_node_completed with nil result" do
    let(:simple_flow) do
      MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end
    end
    let(:empty_execution_log_context) { double("context", execution_log: []) } # rubocop:disable RSpec/VerifiedDoubles
    let(:successful_result) do
      instance_double(Missions::NodeResult, status: :success, next_port: "default", output: "done", variables: {})
    end

    it "skips broadcast when result is nil" do
      mission = create(:mission, flow_data: simple_flow)
      runner = described_class.new(mission)

      # Execute to set up runner state
      run = runner.execute(variables: { "input" => "test" })
      expect(run).to be_completed

      # Directly test the nil guard
      expect { runner.send(:broadcast_node_completed, run, "n1", "test", nil, empty_execution_log_context) }
        .not_to raise_error
    end

    it "broadcasts with nil duration when no matching log entry exists" do
      mission = create(:mission, flow_data: simple_flow)
      runner = described_class.new(mission)
      run = create(:mission_run, mission:, flow_snapshot: simple_flow)
      runner.instance_variable_set(:@node_completion_counts, Hash.new(0))
      entries = []

      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        entries << kwargs[:locals][:entry] if kwargs[:target] == "mission-timeline-entries"
      end

      runner.send(:broadcast_node_completed, run, "n1", "input", successful_result, empty_execution_log_context)

      expect(entries.last[:duration_ms]).to be_nil
    end
  end

  describe "broadcast_run_status" do
    it "does not reload unsaved runs before broadcasting status" do
      mission = create(:mission)
      runner = described_class.new(mission)
      run = build(:mission_run, mission:, status: "pending")

      allow(run).to receive(:reload)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      expect { runner.send(:broadcast_run_status, run, "pending") }.not_to raise_error
      expect(run).not_to have_received(:reload)
    end
  end

  describe "broadcast_remaining_cancelled" do
    it "skips the output node that ended the workflow" do
      mission = create(:mission)
      runner = described_class.new(mission)
      run = build_stubbed(:mission_run, mission:)

      runner.instance_variable_set(:@running_node_ids, Set["out", "worker"])
      allow(runner).to receive(:broadcast_node_state)
      allow(runner).to receive(:broadcast_cancelled_timeline_entry)

      runner.send(:broadcast_remaining_cancelled, run, "out")

      expect(runner).to have_received(:broadcast_node_state).with(run, "worker", nil, "cancelled")
      expect(runner).not_to have_received(:broadcast_node_state).with(run, "out", nil, "cancelled")
      expect(runner).to have_received(:broadcast_cancelled_timeline_entry).with(run, "worker")
      expect(runner).not_to have_received(:broadcast_cancelled_timeline_entry).with(run, "out")
    end

    it "snapshots the running node set before broadcasting cancellations" do
      mission = create(:mission)
      runner = described_class.new(mission)
      run = build_stubbed(:mission_run, mission:)
      running_node_ids = instance_double(Set)

      allow(running_node_ids).to receive(:to_a).and_return(["out", "worker"])
      allow(running_node_ids).to receive(:each).and_raise("live set iteration should not happen")
      runner.instance_variable_set(:@running_node_ids, running_node_ids)
      allow(runner).to receive(:broadcast_node_state)
      allow(runner).to receive(:broadcast_cancelled_timeline_entry)

      expect { runner.send(:broadcast_remaining_cancelled, run, "out") }.not_to raise_error
      expect(runner).to have_received(:broadcast_node_state).with(run, "worker", nil, "cancelled")
    end
  end

  describe "broadcast_all_edges_reset with blank edge ids" do
    it "skips edges with blank ids" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end
      # Add an edge with blank id
      flow["edges"] << { "id" => "", "source" => "t1", "target" => "o1" }
      flow["edges"] << { "id" => nil, "source" => "t1", "target" => "o1" }

      mission = create(:mission, flow_data: flow)
      edge_events = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        edge_events << kwargs[:html] if kwargs[:html]&.include?("data-edge-id")
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      run = described_class.new(mission).execute(variables: { "input" => "test" })
      expect(run).to be_completed

      # Blank/nil edge ids should be omitted from reset events
      reset_events = edge_events.select { |e| e.include?("reset") }
      reset_events.each do |event|
        expect(event).not_to include('data-edge-id=""')
      end
    end

    it "broadcasts reset only for edges with real ids" do
      mission = create(:mission)
      run = create(:mission_run, mission:, flow_snapshot: {
                     "nodes" => [],
                     "edges" => [
                       { "id" => "edge-1", "source" => "a", "target" => "b" },
                       { "id" => "", "source" => "b", "target" => "c" },
                     ],
                   },)
      runner = described_class.new(mission)

      allow(runner).to receive(:safely_broadcast).and_yield
      allow(runner).to receive(:broadcast_edge_state)

      runner.send(:broadcast_all_edges_reset, run)

      expect(runner).to have_received(:broadcast_edge_state).with(run, "edge-1", "reset").once
    end
  end

  describe "resolve_node_label with missing data" do
    it "returns nil when node has no label or name" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
      end
      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)
      run = create(:mission_run, mission:, flow_snapshot: flow)

      # Node "missing" does not exist in flow, so data will be {}
      label = runner.send(:resolve_node_label, run, "nonexistent")
      expect(label).to be_nil
    end

    it "returns nil for a missing node type lookup" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
      end
      mission = create(:mission, flow_data: flow)
      runner = described_class.new(mission)
      run = create(:mission_run, mission:, flow_snapshot: flow)

      expect(runner.send(:resolve_node_type, run, "nonexistent")).to be_nil
    end
  end

  describe "iteration_count_from_context" do
    it "returns iterator total for iterator type" do
      mission = create(:mission)
      runner = described_class.new(mission)
      context = double("context") # rubocop:disable RSpec/VerifiedDoubles
      allow(context).to receive_messages(
        node_outputs: { "iter-1" => [1, 2, 3, 4, 5] },
        execution_log: [],
      )

      count = runner.send(:iteration_count_from_context, context, "iterator", "iter-1")
      expect(count).to eq(5)
    end

    it "returns zero for iterator type when no iterator execution has been logged yet" do
      mission = create(:mission)
      runner = described_class.new(mission)
      context = double("context") # rubocop:disable RSpec/VerifiedDoubles
      allow(context).to receive_messages(node_outputs: {}, execution_log: [])

      count = runner.send(:iteration_count_from_context, context, "iterator", "iter-1")
      expect(count).to eq(0)
    end

    it "counts completed loop-body iterations for loop type" do
      mission = create(:mission)
      runner = described_class.new(mission)
      context = double("context") # rubocop:disable RSpec/VerifiedDoubles
      execution_log = [
        instance_double(Missions::NodeExecution, node_id: "loop-1", node_type: "loop", next_port: "loop"),
        instance_double(Missions::NodeExecution, node_id: "loop-1", node_type: "loop", next_port: "loop"),
        instance_double(Missions::NodeExecution, node_id: "loop-1", node_type: "loop", next_port: "loop"),
        instance_double(Missions::NodeExecution, node_id: "loop-1", node_type: "loop", next_port: "done"),
      ]
      allow(context).to receive(:execution_log).and_return(execution_log)

      count = runner.send(:iteration_count_from_context, context, "loop", "loop-1")
      expect(count).to eq(3)
    end
  end

  describe "control timeline fallback payloads" do
    it "uses node_outputs when no matching control-node log entry exists" do
      mission = create(:mission)
      run = create(:mission_run, mission:, flow_snapshot: {
                     "nodes" => [{ "id" => "loop-1", "type" => "loop", "data" => { "label" => "Loop" } }],
                     "edges" => [],
                   },)
      runner = described_class.new(mission)
      context = instance_double(Missions::ExecutionContext, execution_log: [], node_outputs: { "loop-1" => [1, 2] })
      timeline_entries = []

      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        timeline_entries << kwargs.dig(:locals, :entry) if kwargs[:target] == "mission-timeline-entries"
      end

      runner.send(:broadcast_control_timeline_entry, run, context, "loop-1", "loop", 12.5)

      expect(timeline_entries).to contain_exactly(
        hash_including(
          node_id: "loop-1",
          input: nil,
          output: [1, 2],
          next_port: "done",
        ),
      )
    end
  end

  describe "execution broadcasts" do
    let(:node_events) { [] }
    let(:timeline_entries) { [] }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_events << kwargs[:html] if kwargs[:html]
        timeline_entries << kwargs[:locals][:entry] if kwargs[:target] == "mission-timeline-entries" && kwargs[:locals]
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "broadcasts success state for executed nodes" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "x" => "done" })
        f.node("o1", type: "output")
        f.edge("t1", "sv1")
        f.edge("sv1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_completed
      success = node_events.select { |e| e.include?('"success"') && e.include?("sv1") }
      expect(success).not_to be_empty
    end

    it "broadcasts failure state for invalid nodes" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("cond1", type: "condition") # no expression → fails
        f.edge("t1", "cond1")
      end

      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "hi" })

      expect(run).to be_failed
      failure_events = node_events.select { |e| e.include?('"failure"') && e.include?("cond1") }
      expect(failure_events).not_to be_empty
    end
  end

  describe "timeline entry broadcasting for every executed node" do
    let(:flow) do
      MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "step" => "one" })
        f.node("sv2", type: "set_variable", assignments: { "step" => "two" })
        f.node("o1", type: "output")
        f.edge("t1", "sv1")
        f.edge("sv1", "sv2")
        f.edge("sv2", "o1")
      end
    end

    let(:timeline_entries) { [] }
    let(:node_state_events) { [] }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_state_events << kwargs[:html] if kwargs[:html]
        timeline_entries << kwargs[:locals][:entry] if kwargs[:target] == "mission-timeline-entries" && kwargs[:locals]
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "broadcasts a timeline entry for each non-output node" do
      mission = create(:mission, flow_data: flow)
      run = described_class.new(mission).execute(variables: { "input" => "test" })

      expect(run).to be_completed
      timeline_node_ids = timeline_entries.pluck(:node_id)
      expect(timeline_node_ids).to include("t1", "sv1", "sv2")
    end

    it "includes required fields in every timeline entry" do
      mission = create(:mission, flow_data: flow)
      described_class.new(mission).execute(variables: { "input" => "test" })

      timeline_entries.each do |entry|
        expect(entry).to include(:node_id, :node_type, :status, :input, :output, :duration_ms)
        expect(entry[:status]).to eq("success")
      end
    end

    it "broadcasts resolved node input in timeline entries" do
      mission = create(:mission, flow_data: flow)
      described_class.new(mission).execute(variables: { "input" => "test" })

      set_variable_entry = timeline_entries.find { |entry| entry[:node_id] == "sv1" }
      expect(set_variable_entry[:input]).to eq({ "assignments" => { "step" => "one" } })
    end

    it "broadcasts success node state events for each node" do
      mission = create(:mission, flow_data: flow)
      described_class.new(mission).execute(variables: { "input" => "test" })

      ["t1", "sv1", "sv2"].each do |node_id|
        success_events = node_state_events.select { |e| e.include?(node_id) && e.include?('"success"') }
        expect(success_events).not_to be_empty, "Expected success state event for node #{node_id}"
      end
    end
  end

  describe "cancellation during node execution" do
    let(:node_state_events) { [] }
    let(:timeline_entries) { [] }
    let(:cancel_flow) do
      MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("sv1", type: "set_variable", assignments: { "x" => "1" })
        f.node("sv2", type: "set_variable", assignments: { "y" => "2" })
        f.edge("t1", "sv1")
        f.edge("sv1", "sv2")
      end
    end
    let(:mission) { create(:mission, flow_data: cancel_flow) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
        node_state_events << kwargs[:html] if kwargs[:html]
        timeline_entries << kwargs[:locals][:entry] if kwargs[:target] == "mission-timeline-entries" && kwargs[:locals]
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      # Cancel the run while sv1 is executing (simulate concurrent cancel request)
      allow_any_instance_of(Missions::Nodes::SetVariable).to receive(:execute).and_wrap_original do |m, *args| # rubocop:disable RSpec/AnyInstance
        result = m.call(*args)
        MissionRun.last.update!(status: :cancelled, completed_at: Time.current)
        result
      end
    end

    it "broadcasts cancelled state when run is cancelled during node execution" do
      run = described_class.new(mission).resume_or_execute(
        mission.mission_runs.create!(status: :pending, flow_snapshot: cancel_flow),
        variables: { "input" => "test" },
      )

      expect(run.reload).to be_cancelled

      sv1_node_events = node_state_events.select { |e| e.include?("data-node-id") && e.include?("sv1") }
      expect(sv1_node_events.last).to include('"cancelled"')

      sv2_node_events = node_state_events.select { |e| e.include?("data-node-id") && e.include?("sv2") }
      expect(sv2_node_events).to be_empty

      sv1_timeline = timeline_entries.select { |e| e[:node_id] == "sv1" && e[:status] == "cancelled" }
      expect(sv1_timeline).not_to be_empty
    end
  end
end
