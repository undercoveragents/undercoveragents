# frozen_string_literal: true

require "rails_helper"
require "support/mission_flow_builder"

module Missions
  module Nodes
    class AsyncIteratorProbe
      include MissionNodePlugin

      class << self
        def node_type = "async_iterator_probe"
        def node_label = "Async Iterator Probe"
        def node_icon = "fa-solid fa-vial"
        def node_color = "#0f766e"
        def node_category = :node
        def node_description = "Test node that yields while inspecting iterator runtime helpers"

        def reset_tracking!
          @active_calls = 0
          @peak_active = 0
          @completion_order = []
        end

        def peak_active
          @peak_active || 0
        end

        def completion_order
          @completion_order || []
        end

        def mark_started!
          @active_calls ||= 0
          @peak_active ||= 0
          @active_calls += 1
          @peak_active = [@peak_active, @active_calls].max
        end

        def mark_finished!(item)
          @completion_order ||= []
          @completion_order << item
          @active_calls -= 1
        end
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        item = context.get_variable("item")
        index = context.get_variable("index")

        self.class.mark_started!
        pause_for(item)

        return failure_result(item) if node_data["fail_on"].to_s == item.to_s

        NodeResult.new(
          status: :success,
          output: {
            "item" => item,
            "index" => index,
            "current_input" => context.current_input,
          },
        )
      ensure
        self.class.mark_finished!(item) if item.present?
      end

      private

      def failure_result(item)
        NodeResult.new(status: :failure, output: "Probe failed for #{item}")
      end

      def pause_for(item)
        sleep(delay_for(item))
      end

      def delay_for(item)
        {
          "a" => 0.03,
          "b" => 0.01,
          "c" => 0.03,
          "d" => 0.01,
          "e" => 0.02,
          "f" => 0.02,
        }.fetch(item.to_s, 0.01)
      end
    end
  end
end

RSpec.describe Missions::Runner do
  before do
    Missions::Nodes::AsyncIteratorProbe.reset_tracking!
    next if MissionNodePlugin.type_map.key?("async_iterator_probe")

    MissionNodePlugin.register(
      "async_iterator_probe", "Missions::Nodes::AsyncIteratorProbe",
      label: "Async Iterator Probe", icon: "fa-solid fa-vial", color: "#0f766e",
      category: :node, description: "Test node that yields while inspecting iterator runtime helpers",
    )
  end

  after do
    MissionNodePlugin.restore_defaults!
  end

  def build_probe_flow(parallel: nil, max_parallel_branches: nil, fail_on: nil)
    MissionFlowBuilder.build do |f|
      iterator_data = { name: "parallel_iter", collection: "items" }
      iterator_data[:parallel] = parallel unless parallel.nil?
      iterator_data[:max_parallel_branches] = max_parallel_branches unless max_parallel_branches.nil?

      probe_data = {}
      probe_data[:fail_on] = fail_on if fail_on.present?

      f.node("input", type: "input")
      f.node("iter", type: "iterator", **iterator_data)
      f.node("probe", type: "async_iterator_probe", name: "per_item_probe", **probe_data)
      f.node("output", type: "output")
      f.edge("input", "iter")
      f.edge("iter", "probe", source_handle: "loop")
      f.edge("iter", "output", source_handle: "done")
    end
  end

  def expected_probe_results(items)
    items.each_with_index.map do |item, index|
      {
        "item" => item,
        "index" => index,
        "current_input" => item,
      }
    end
  end

  def execute_probe_flow(items:, **)
    mission = create(:mission, flow_data: build_probe_flow(**))
    described_class.new(mission).execute(variables: { "input" => "seed", "items" => items })
  end

  def build_parallel_llm_flow(connector) # rubocop:disable Metrics/MethodLength
    MissionFlowBuilder.build do |f|
      f.node("input", type: "input")
      f.node(
        "iter",
        type: "iterator",
        name: "reviews",
        collection: "items",
        parallel: true,
        max_parallel_branches: 2,
      )
      f.node(
        "llm",
        type: "llm",
        name: "review_text",
        connector_id: connector.id.to_s,
        model: "gpt-4.1",
        prompt: "Review {{item}}",
      )
      f.node("output", type: "output")
      f.edge("input", "iter")
      f.edge("iter", "llm", source_handle: "loop")
      f.edge("iter", "output", source_handle: "done")
    end
  end

  def build_parallel_delay_join_flow
    MissionFlowBuilder.build do |f|
      f.node("input", type: "input")
      f.node(
        "iter",
        type: "iterator",
        name: "parallel_iter",
        collection: "items",
        parallel: true,
        max_parallel_branches: 2,
      )
      f.node("delay", type: "delay", name: "per_item_delay", duration: 0.02)
      f.node("fast_path", type: "set_variable", name: "fast_path", variables: { ready: true })
      f.node("output", type: "output")
      f.edge("input", "iter")
      f.edge("input", "fast_path")
      f.edge("iter", "delay", source_handle: "loop")
      f.edge("iter", "output", source_handle: "done")
      f.edge("fast_path", "output")
    end
  end

  def stub_parallel_llm_chat(connector) # rubocop:disable Metrics/AbcSize
    allow(connector).to receive(:build_context).and_return(double.as_null_object)

    state = { active_calls: 0, peak_calls: 0 }

    allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:ask) do |_chat, message, **_opts| # rubocop:disable RSpec/AnyInstance
      state[:active_calls] += 1
      state[:peak_calls] = [state[:peak_calls], state[:active_calls]].max

      sleep({ "alpha" => 0.03, "beta" => 0.01, "gamma" => 0.02 }.fetch(message.to_s, 0.01))

      instance_double(RubyLLM::Message, content: "review:#{message}")
    ensure
      state[:active_calls] -= 1
    end

    state
  end

  it "keeps iterator execution sequential by default" do
    items = ["a", "b", "c"]

    run = execute_probe_flow(items:)

    expect(run).to be_completed
    expect(Missions::Nodes::AsyncIteratorProbe.peak_active).to eq(1)
    expect(Missions::Nodes::AsyncIteratorProbe.completion_order).to eq(items)
    expect(run.variables["output"]).to eq(expected_probe_results(items))
  end

  it "caps default parallel iterator concurrency at five branches" do
    run = execute_probe_flow(items: ["a", "b", "c", "d", "e", "f"], parallel: true)

    expect(run).to be_completed
    expect(Missions::Nodes::AsyncIteratorProbe.peak_active)
      .to be_between(2, Missions::Nodes::Iterator::DEFAULT_MAX_PARALLEL_BRANCHES).inclusive
  end

  it "falls back to the default parallel limit for legacy iterator state without a configured limit" do
    runner = described_class.new(create(:mission))

    expect(runner.send(:iterator_parallel_limit, {})).to eq(Missions::Nodes::Iterator::DEFAULT_MAX_PARALLEL_BRANCHES)
  end

  it "uses the configured parallel limit when iterator state provides one" do
    runner = described_class.new(create(:mission))

    expect(runner.send(:iterator_parallel_limit, { "max_parallel_branches" => "7" })).to eq(7)
  end

  it "returns no iterator batches when the resume index is already beyond the collection" do
    runner = described_class.new(create(:mission))

    expect(runner.send(:iterator_batches, 2, 2, 5)).to eq([])
  end

  it "halts parallel iterator batching when execution capacity is already exhausted" do
    runner = described_class.new(create(:mission))
    run = instance_double(MissionRun)
    context = instance_double(Missions::ExecutionContext)
    scheduler = instance_double(
      Missions::RunnerScheduler,
      execution_count: Missions::ExecutionCounter.new(value: described_class::MAX_TOTAL_EXECUTIONS),
    )

    allow(run).to receive_messages(reload: run, cancelled?: false)
    allow(context).to receive(:iterator_state).with("iter").and_return({ "max_parallel_branches" => 2 })
    allow(runner).to receive(:persist_iterator_progress)
    allow(runner).to receive(:execute_parallel_iterator_batch)

    runner.send(:execute_parallel_iterator_iterations, run, nil, context, "iter", ["a", "b"], 0, [], scheduler)

    expect(runner).not_to have_received(:persist_iterator_progress)
    expect(runner).not_to have_received(:execute_parallel_iterator_batch)
  end

  it "preserves ordered iterator results even when parallel iterations finish out of order" do
    items = ["a", "b", "c", "d"]

    run = execute_probe_flow(items:, parallel: true, max_parallel_branches: 2)

    expect(run).to be_completed
    expect(Missions::Nodes::AsyncIteratorProbe.peak_active).to eq(2)
    expect(Missions::Nodes::AsyncIteratorProbe.completion_order.first(2)).to eq(["b", "a"])
    expect(run.execution_state.dig("node_variables", "parallel_iter", "results")).to eq(expected_probe_results(items))
    expect(run.variables["output"]).to eq(expected_probe_results(items))
  end

  it "fails the run when one parallel iteration branch fails" do
    run = execute_probe_flow(items: ["a", "boom", "c"], parallel: true, max_parallel_branches: 2, fail_on: "boom")

    expect(run).to be_failed
    expect(run.error).to include("Probe failed for boom")
  end

  it "supports real LLM-backed iterator workflows in parallel mode" do
    connector = create(:connector, :llm_provider, :enabled)
    create(:model, model_id: "gpt-4.1", provider: connector.provider)
    llm_state = stub_parallel_llm_chat(connector)

    mission = create(:mission, flow_data: build_parallel_llm_flow(connector))
    run = described_class.new(mission).execute(
      variables: { "input" => "seed", "items" => ["alpha", "beta", "gamma"] },
    )

    expect(run).to be_completed
    expect(llm_state[:peak_calls]).to eq(2)
    expect(run.execution_state.dig("node_variables", "reviews", "results")).to eq(
      ["review:alpha", "review:beta", "review:gamma"],
    )
    expect(run.variables["output"]).to eq(["review:alpha", "review:beta", "review:gamma"])
  end

  it "waits for parallel delay branches before following the iterator done path" do
    mission = create(:mission, flow_data: build_parallel_delay_join_flow)

    run = described_class.new(mission).execute(
      variables: { "input" => "seed", "items" => [1, 2, 3] },
    )

    expect(run).to be_completed
    expect(run.execution_state.fetch("execution_log").count { |entry| entry["node_type"] == "delay" }).to eq(3)
    expect(run.execution_state.dig("node_variables", "parallel_iter", "results")).to eq(
      ["Waited 0.02s", "Waited 0.02s", "Waited 0.02s"],
    )
    expect(run.variables["output"]).to eq(["Waited 0.02s", "Waited 0.02s", "Waited 0.02s"])
  end
end
