# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::FlowHistory do
  let(:mission) { create(:mission) }
  let(:snapshot_a) { { "nodes" => [{ "id" => "n-a" }], "edges" => [] } }
  let(:snapshot_b) { { "nodes" => [{ "id" => "n-b" }], "edges" => [] } }

  describe "#push_undo_snapshot!" do
    it "appends the snapshot to flow_undo_history and clears redo history" do
      mission.update!(flow_redo_history: [snapshot_b])
      mission.push_undo_snapshot!(snapshot_a)

      expect(mission.reload.flow_undo_history).to eq([snapshot_a])
      expect(mission.reload.flow_redo_history).to be_empty
    end

    it "keeps at most HISTORY_LIMIT entries by dropping the oldest" do
      full_history = Array.new(Missions::FlowHistory::HISTORY_LIMIT) { |i| { "nodes" => [{ "id" => "n#{i}" }], "edges" => [] } }
      mission.update!(flow_undo_history: full_history)

      mission.push_undo_snapshot!(snapshot_a)

      loaded = mission.reload.flow_undo_history
      expect(loaded.length).to eq(Missions::FlowHistory::HISTORY_LIMIT)
      expect(loaded.last).to eq(snapshot_a)
    end

    it "appends successive snapshots in order" do
      mission.push_undo_snapshot!(snapshot_a)
      mission.push_undo_snapshot!(snapshot_b)

      expect(mission.reload.flow_undo_history).to eq([snapshot_a, snapshot_b])
    end
  end

  describe "#can_undo?" do
    it "returns false when undo history is empty" do
      expect(mission.can_undo?).to be(false)
    end

    it "returns true when undo history has entries" do
      mission.update!(flow_undo_history: [snapshot_a])
      expect(mission.can_undo?).to be(true)
    end
  end

  describe "#can_redo?" do
    it "returns false when redo history is empty" do
      expect(mission.can_redo?).to be(false)
    end

    it "returns true when redo history has entries" do
      mission.update!(flow_redo_history: [snapshot_a])
      expect(mission.can_redo?).to be(true)
    end
  end
end
