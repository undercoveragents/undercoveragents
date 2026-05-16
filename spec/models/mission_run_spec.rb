# frozen_string_literal: true

# == Schema Information
#
# Table name: mission_runs
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  callback_url            :string
#  completed_at            :datetime
#  error                   :text
#  execution_state         :jsonb            not null
#  flow_snapshot           :jsonb            not null
#  started_at              :datetime
#  status                  :string           default("pending"), not null
#  trigger_data            :jsonb            not null
#  variables               :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  api_client_id           :bigint
#  channel_conversation_id :bigint
#  channel_id              :bigint
#  channel_target_id       :bigint
#  current_node_id         :string
#  mission_id              :bigint           not null
#
# Indexes
#
#  index_mission_runs_on_api_client_id            (api_client_id)
#  index_mission_runs_on_channel_conversation_id  (channel_conversation_id)
#  index_mission_runs_on_channel_id               (channel_id)
#  index_mission_runs_on_channel_target_id        (channel_target_id)
#  index_mission_runs_on_mission_id               (mission_id)
#  index_mission_runs_on_mission_id_and_status    (mission_id,status)
#  index_mission_runs_on_status                   (status)
#
# Foreign Keys
#
#  fk_rails_...  (api_client_id => api_clients.id)
#  fk_rails_...  (channel_conversation_id => channel_conversations.id)
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (channel_target_id => channel_targets.id)
#  fk_rails_...  (mission_id => missions.id)
#
require "rails_helper"

RSpec.describe MissionRun do
  describe ".ransackable_associations" do
    it "returns the associations ransack can search" do
      expect(described_class.ransackable_associations).to eq(["mission"])
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:mission) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class.statuses.keys) }
  end

  describe "scopes" do
    it "active includes pending, running, and paused" do
      mission = create(:mission)
      pending_run  = create(:mission_run, mission:, status: "pending")
      running_run  = create(:mission_run, mission:, status: "running")
      paused_run   = create(:mission_run, mission:, status: "paused")
      completed_run = create(:mission_run, mission:, status: "completed")

      active = described_class.active
      expect(active).to include(pending_run, running_run, paused_run)
      expect(active).not_to include(completed_run)
    end

    it "finished includes completed, failed, and cancelled" do
      mission = create(:mission)
      completed_run  = create(:mission_run, mission:, status: "completed")
      failed_run     = create(:mission_run, mission:, status: "failed")
      cancelled_run  = create(:mission_run, mission:, status: "cancelled")
      running_run    = create(:mission_run, mission:, status: "running")

      finished = described_class.finished
      expect(finished).to include(completed_run, failed_run, cancelled_run)
      expect(finished).not_to include(running_run)
    end
  end

  describe "status predicates" do
    it "returns the correct boolean for each status" do
      mission = create(:mission)
      finished = ["completed", "failed", "cancelled"]
      active = ["pending", "running", "paused"]
      (active + finished).each do |s|
        run = create(:mission_run, mission:, status: s)
        expect(run.public_send(:"#{s}?")).to be(true)
        expect(run.finished?).to eq(finished.include?(s))
        expect(run.active?).to eq(active.include?(s))
      end
    end
  end

  describe "#duration" do
    it "returns nil when started_at is absent" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "pending", started_at: nil)
      expect(run.duration).to be_nil
    end

    it "returns elapsed seconds from started_at to completed_at" do
      mission = create(:mission)
      start = 10.seconds.ago
      run = create(:mission_run, mission:, status: "completed",
                                 started_at: start, completed_at: start + 5,)
      expect(run.duration).to be_within(0.1).of(5)
    end

    it "returns seconds since started_at when not yet completed" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "running", started_at: 3.seconds.ago)
      expect(run.duration).to be_within(1).of(3)
    end
  end

  describe "#flow_snapshot=" do
    it "normalizes JSON string payloads" do
      run = described_class.new

      run.flow_snapshot = '{"nodes":[{"id":"n1","type":"input"}],"edges":[]}'

      expect(run.flow_snapshot).to eq({
                                        "nodes" => [
                                          { "id" => "n1", "type" => "input", "position" => { "x" => 0, "y" => 0 } },
                                        ],
                                        "edges" => [],
                                      })
    end

    it "falls back to an empty normalized flow for invalid JSON" do
      run = described_class.new

      run.flow_snapshot = "{bad-json}"

      expect(run.flow_snapshot).to eq({ "nodes" => [], "edges" => [] })
    end
  end

  describe "#node_executions" do
    it "returns an empty array when execution_state has no log" do
      mission = create(:mission)
      run = create(:mission_run, mission:, status: "pending", execution_state: {})
      expect(run.node_executions).to eq([])
    end

    it "deserializes the execution log into NodeExecution objects" do
      mission = create(:mission)
      log = [
        {
          "node_id" => "n1", "node_type" => "input",
          "input" => { "fields" => { "message" => "Hello" } },
          "status" => "success", "output" => "hello",
          "next_port" => "default", "started_at" => Time.current.iso8601(3),
          "finished_at" => Time.current.iso8601(3), "error" => nil,
        },
      ]
      run = create(:mission_run, mission:, status: "completed",
                                 execution_state: { "execution_log" => log },)

      executions = run.node_executions
      expect(executions.size).to eq(1)
      expect(executions.first.node_id).to eq("n1")
      expect(executions.first.input).to eq({ "fields" => { "message" => "Hello" } })
      expect(executions.first.status).to eq(:success)
    end

    it "handles entries with nil timestamps" do
      mission = create(:mission)
      log = [
        {
          "node_id" => "n2", "node_type" => "set_variable",
          "status" => "success", "output" => nil,
          "next_port" => "default", "started_at" => nil,
          "finished_at" => nil, "error" => nil,
        },
      ]
      run = create(:mission_run, mission:, status: "completed",
                                 execution_state: { "execution_log" => log },)

      executions = run.node_executions
      expect(executions.first.started_at).to be_nil
      expect(executions.first.finished_at).to be_nil
    end

    it "handles entries with nil status" do
      mission = create(:mission)
      log = [
        {
          "node_id" => "n3", "node_type" => "agent",
          "status" => nil, "output" => nil,
          "next_port" => nil, "started_at" => nil,
          "finished_at" => nil, "error" => nil,
        },
      ]
      run = create(:mission_run, mission:, status: "running",
                                 execution_state: { "execution_log" => log },)

      executions = run.node_executions
      expect(executions.first.status).to be_nil
    end
  end
end
