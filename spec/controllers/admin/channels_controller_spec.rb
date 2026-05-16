# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ChannelsController do
  describe "private helpers" do
    subject(:channels_controller) { controller_class.new }

    let(:controller_class) do
      Class.new(described_class) do
        attr_writer :test_flash, :test_params, :test_target_params, :test_scoped_agents, :test_scoped_missions

        def flash = @test_flash || super
        def params = @test_params || super
        def target_params = @test_target_params || super
        def scoped_agents = @test_scoped_agents || super
        def scoped_missions = @test_scoped_missions || super
      end
    end

    it "preserves non-blank connector ids in channel params" do
      channels_controller.test_params = ActionController::Parameters.new(channel: { name: "API", connector_id: "42" })

      expect(channels_controller.send(:channel_params)[:connector_id]).to eq("42")
    end

    it "returns nil for unsupported selected target kinds" do
      channels_controller.test_target_params = ActionController::Parameters.new(target_kind: "unknown")

      expect(channels_controller.send(:selected_target_record)).to be_nil
    end

    it "does not flash a token when the generated credential has no raw token" do
      channel = build_stubbed(:channel, :api)
      credentials = instance_double(ActiveRecord::Associations::CollectionProxy, exists?: false)
      flashed = {}

      allow(channel).to receive(:channel_credentials).and_return(credentials)
      allow(credentials).to receive(:create!).and_return(instance_double(ChannelCredential, raw_token: nil))
      channels_controller.test_flash = flashed
      channels_controller.instance_variable_set(:@channel, channel)

      channels_controller.send(:ensure_primary_credential!)

      expect(flashed).to be_empty
    end

    it "returns nil for default target agent and mission ids when no default target exists" do
      expect(channels_controller.send(:default_target_agent_id, nil)).to be_nil
      expect(channels_controller.send(:default_target_mission_id, nil)).to be_nil
    end

    it "returns early when upserting the default target without a selected target" do
      channel = create(:channel, :api)
      empty_agents = instance_double(ActiveRecord::Relation, find_by: nil)

      channels_controller.instance_variable_set(:@channel, channel)
      channels_controller.test_target_params = ActionController::Parameters.new(target_kind: "agent", agent_id: "")
      channels_controller.test_scoped_agents = empty_agents

      expect { channels_controller.send(:upsert_default_target!) }.not_to change(ChannelTarget, :count)
    end

    it "upserts the default target and demotes older defaults" do
      tenant = create(:tenant).tap(&:ensure_core_resources!)
      operation = tenant.default_operation
      channel = create(:channel, :api, tenant:)
      previous_agent = create(:agent, operation:)
      stale_agent = create(:agent, operation:)
      next_agent = create(:agent, operation:)
      create(:channel_target, channel:, target: previous_agent, default: true, position: 4)
      stale_target = create(:channel_target, channel:, target: stale_agent, default: true, position: 5)
      scoped_agents = instance_double(ActiveRecord::Relation, find_by: next_agent)

      channels_controller.instance_variable_set(:@channel, channel)
      channels_controller.test_target_params = ActionController::Parameters.new(
        target_kind: "agent",
        agent_id: next_agent.id,
      )
      channels_controller.test_scoped_agents = scoped_agents

      channels_controller.send(:upsert_default_target!)

      expect(channel.reload.default_target.target).to eq(next_agent)
      expect(channel.default_target.position).to eq(0)
      expect(channel.channel_targets.where(default: true).count).to eq(1)
      expect(stale_target.reload.default).to be(false)
    end
  end
end
