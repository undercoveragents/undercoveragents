# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::RunnerScheduler do
  describe ".start" do
    it "seeds a scheduler with an initial work item" do
      scheduler = described_class.start(
        node_id: "node-1",
        incoming_edge_id: "edge-1",
        runtime_state: { "item" => 1 },
      )
      work_item = scheduler.dequeue

      expect(work_item.node_id).to eq("node-1")
      expect(work_item.incoming_edge_id).to eq("edge-1")
      expect(work_item.runtime_state).to eq({ "item" => 1 })
      expect(scheduler).to be_empty
    end
  end

  describe ".restore" do
    let(:execution_count) { Missions::ExecutionCounter.new(value: 4) }

    it "restores active and ready work from a persisted frontier" do
      scheduler = described_class.restore(
        frontier_id: "frontier-1",
        frontier_state: {
          "ready" => [{ "node_id" => "node-2", "incoming_edge_id" => "edge-2", "runtime_state" => { "item" => 2 } }],
          "active" => { "node_id" => "node-1", "incoming_edge_id" => "edge-1", "runtime_state" => { "item" => 1 } },
        },
        execution_count:,
        context: nil,
      )
      first_item = scheduler.dequeue
      scheduler.complete_active_work_item
      second_item = scheduler.dequeue
      expect(scheduler.frontier_id).to eq("frontier-1")
      expect(scheduler.execution_count).to be(execution_count)
      expect(first_item.to_h).to eq(
        { "node_id" => "node-1", "incoming_edge_id" => "edge-1", "runtime_state" => { "item" => 1 } },
      )
      expect(second_item.to_h).to eq(
        { "node_id" => "node-2", "incoming_edge_id" => "edge-2", "runtime_state" => { "item" => 2 } },
      )
    end
  end

  describe "#enqueue and #dequeue" do
    it "processes work items in FIFO order" do
      scheduler = described_class.new
      scheduler.enqueue("first", incoming_edge_id: "edge-1", runtime_state: { "item" => 1 })
      scheduler.enqueue("second", incoming_edge_id: "edge-2", runtime_state: { "item" => 2 })

      first_item = scheduler.dequeue
      scheduler.complete_active_work_item
      second_item = scheduler.dequeue

      expect(first_item.node_id).to eq("first")
      expect(first_item.incoming_edge_id).to eq("edge-1")
      expect(second_item.node_id).to eq("second")
      expect(second_item.incoming_edge_id).to eq("edge-2")
      expect(scheduler.dequeue).to be_nil
    end

    it "compacts processed queue entries after enough dequeues" do
      scheduler = described_class.new
      64.times { |index| scheduler.enqueue("node-#{index}") }

      33.times { scheduler.dequeue }
      next_item = scheduler.dequeue

      expect(next_item.node_id).to eq("node-33")
    end
  end

  describe "#fork" do
    it "shares the execution counter and can start empty or seeded" do
      parent = described_class.new
      parent.execution_count.increment

      empty_branch = parent.fork
      seeded_branch = parent.fork(node_id: "child", incoming_edge_id: "edge-1")

      expect(empty_branch.execution_count).to be(parent.execution_count)
      expect(empty_branch).to be_empty
      expect(seeded_branch.execution_count).to be(parent.execution_count)
      expect(seeded_branch.dequeue.node_id).to eq("child")
    end
  end

  describe "frontier synchronization" do
    let(:run) { create(:mission_run, mission: create(:mission)) }
    let(:context) { Missions::ExecutionContext.new(mission_run: run) }

    let(:scheduler) do
      described_class.start(
        node_id: "node-1",
        incoming_edge_id: "edge-1",
        runtime_state: { "item" => 1 },
        execution_count: Missions::ExecutionCounter.new(value: 3),
        context:,
      )
    end

    it "syncs ready work into the execution context" do
      ready_frontier = context.scheduler_frontiers.fetch(scheduler.frontier_id)

      expect(ready_frontier["ready"]).to contain_exactly(
        {
          "node_id" => "node-1",
          "incoming_edge_id" => "edge-1",
          "runtime_state" => { "item" => 1 },
        },
      )
      expect(ready_frontier["active"]).to be_nil
      expect(context.execution_count_value).to eq(3)
    end

    it "syncs active work and clears empty frontier state" do
      scheduler.dequeue
      scheduler.refresh_active_work_item(runtime_state: { "item" => 2 })

      active_frontier = context.scheduler_frontiers.fetch(scheduler.frontier_id)

      expect(active_frontier["ready"]).to eq([])
      expect(active_frontier["active"]).to eq(
        {
          "node_id" => "node-1",
          "incoming_edge_id" => "edge-1",
          "runtime_state" => { "item" => 2 },
        },
      )

      scheduler.complete_active_work_item

      expect(context.scheduler_frontiers).to eq({})
    end

    it "ignores active work refresh when nothing is running" do
      scheduler
      ready_frontiers = context.scheduler_frontiers.deep_dup

      scheduler.refresh_active_work_item(runtime_state: { "item" => 2 })

      expect(context.scheduler_frontiers).to eq(ready_frontiers)
    end
  end

  describe ".build_work_item" do
    it "accepts symbol keys and defaults optional fields" do
      work_item = described_class.send(:build_work_item, { node_id: :node_one, runtime_state: { item: 1 } })

      expect(work_item).to have_attributes(
        node_id: "node_one",
        incoming_edge_id: nil,
        runtime_state: { "item" => 1 },
      )
    end

    it "requires a node id" do
      expect { described_class.send(:build_work_item, {}) }.to raise_error(KeyError)
    end
  end
end
