# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::LimitEnforcer do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:model_record) { create(:model) }
  let(:chat) { create(:chat, tenant:, operation:, model: model_record) }

  def build_enforcer(user:, agent:, mission:, channel:)
    described_class.new(
      tenant:,
      operation:,
      user:,
      agent:,
      mission:,
      channel:,
      model_id: model_record.id,
      execution_context: "application",
    )
  end

  def target_match_results(enforcer, user:, agent:, mission:, channel:)
    {
      user: enforcer.send(:user_limit_matches?, create(:cost_limit, tenant:, target_type: "user", target_id: user.id)),
      user_mismatch: enforcer.send(
        :user_limit_matches?,
        create(:cost_limit, tenant:, target_type: "user", target_id: create(:user, tenant:).id),
      ),
      agent: enforcer.send(
        :agent_limit_matches?,
        create(:cost_limit, tenant:, target_type: "agent", target_id: agent.id),
      ),
      mission: enforcer.send(
        :mission_limit_matches?,
        create(:cost_limit, tenant:, target_type: "mission", target_id: mission.id),
      ),
      channel: enforcer.send(
        :channel_limit_matches?,
        create(:cost_limit, tenant:, target_type: "channel", target_id: channel.id),
      ),
    }
  end

  def base_match_results(enforcer)
    operation_match_results(enforcer).merge(other_match_results(enforcer))
  end

  def operation_match_results(enforcer)
    nil_context_enforcer = build_nil_operation_enforcer

    {
      operation: enforcer.send(:operation_limit_matches?, create(:cost_limit, :for_operation, tenant:, operation:)),
      operation_scoped_match: enforcer.send(
        :limit_matches_context?,
        create(:cost_limit, :for_operation, tenant:, operation:),
      ),
      operation_mismatch: enforcer.send(
        :limit_matches_context?,
        create(:cost_limit, :for_operation, tenant:, operation: create(:operation, tenant:)),
      ),
      operation_without_scope: enforcer.send(:limit_matches_context?, create(:cost_limit, :hard_stop, tenant:)),
    }.merge(nil_operation_match_results(nil_context_enforcer))
  end

  def nil_operation_match_results(enforcer)
    {
      operation_nil_context: enforcer.send(
        :operation_limit_matches?,
        create(:cost_limit, :for_operation, tenant:, operation:),
      ),
      operation_nil_scoped_match: enforcer.send(
        :limit_matches_context?,
        create(:cost_limit, :for_operation, tenant:, operation:),
      ),
    }
  end

  def other_match_results(enforcer)
    {
      tenant: enforcer.send(:limit_matches_context?, create(:cost_limit, tenant:)),
      model: enforcer.send(
        :model_limit_matches?,
        create(:cost_limit, tenant:, target_type: "model", target_id: model_record.id),
      ),
      execution_context: enforcer.send(
        :execution_context_limit_matches?,
        create(:cost_limit, tenant:, target_type: "execution_context", target_key: "application"),
      ),
      unknown: enforcer.send(:limit_matches_context?, build(:cost_limit, tenant:, target_type: "unknown")),
    }
  end

  def build_nil_operation_enforcer
    described_class.new(
      tenant:,
      operation: nil,
      user: nil,
      agent: nil,
      mission: nil,
      channel: nil,
      model_id: model_record.id,
      execution_context: "application",
    )
  end

  def nil_context_match_results(enforcer, user:, agent:, mission:, channel:)
    {
      user_nil_context: enforcer.send(:user_limit_matches?,
                                      create(:cost_limit, tenant:, target_type: "user", target_id: user.id),),
      agent_nil_context: enforcer.send(:agent_limit_matches?,
                                       create(:cost_limit, tenant:, target_type: "agent", target_id: agent.id),),
      mission_nil_context: enforcer.send(:mission_limit_matches?,
                                         create(:cost_limit, tenant:, target_type: "mission", target_id: mission.id),),
      channel_nil_context: enforcer.send(:channel_limit_matches?,
                                         create(:cost_limit, tenant:, target_type: "channel", target_id: channel.id),),
    }
  end

  def expected_match_results
    expected_operation_results.merge(expected_target_results)
  end

  def expected_operation_results
    {
      tenant: true,
      operation: true,
      operation_nil_context: false,
      operation_nil_scoped_match: false,
      operation_scoped_match: true,
      operation_mismatch: false,
      operation_without_scope: true,
      model: true,
      execution_context: true,
      unknown: false,
    }
  end

  def expected_target_results
    {
      user: true,
      user_mismatch: false,
      user_nil_context: false,
      agent: true,
      agent_nil_context: false,
      mission: true,
      mission_nil_context: false,
      channel: true,
      channel_nil_context: false,
    }
  end

  it "raises when a matching hard-stop limit is exceeded" do
    create(:message, chat:, model: model_record).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: 12,
      cost_calculated_at: Time.current,
    )
    create(:cost_limit, :hard_stop, tenant:, period: "all_time", amount_usd: 10)

    expect { chat.check_cost_limits! }.to raise_error(
      Costs::LimitEnforcer::Error,
      /Cost limit exceeded/,
    )
  end

  it "ignores warn-only exceeded limits" do
    create(:message, chat:, model: model_record).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: 12,
      cost_calculated_at: Time.current,
    )
    create(:cost_limit, tenant:, period: "all_time", amount_usd: 10, enforcement_mode: "warn_only")

    expect { chat.check_cost_limits! }.not_to raise_error
  end

  it "matches every supported target type against the runtime context" do
    user = create(:user, tenant:)
    agent = create(:agent, operation:)
    mission = create(:mission, operation:)
    channel = create(:channel, operation:)
    enforcer = build_enforcer(user:, agent:, mission:, channel:)
    nil_context_enforcer = build_enforcer(user: nil, agent: nil, mission: nil, channel: nil)

    results = base_match_results(enforcer)
              .merge(target_match_results(enforcer, user:, agent:, mission:, channel:))
              .merge(nil_context_match_results(nil_context_enforcer, user:, agent:, mission:, channel:))

    expect(results).to eq(expected_match_results)
  end
end
