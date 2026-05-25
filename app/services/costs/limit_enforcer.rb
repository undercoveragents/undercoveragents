# frozen_string_literal: true

module Costs
  class LimitEnforcer
    class Error < StandardError; end

    TARGET_MATCHERS = {
      "tenant" => :tenant_limit_matches?,
      "operation" => :operation_limit_matches?,
      "user" => :user_limit_matches?,
      "agent" => :agent_limit_matches?,
      "mission" => :mission_limit_matches?,
      "channel" => :channel_limit_matches?,
      "model" => :model_limit_matches?,
      "execution_context" => :execution_context_limit_matches?,
    }.freeze

    def self.check!(**context)
      new(**context).check!
    end

    def initialize(**context)
      @context = context
    end

    def check!
      exceeded_limit = matching_limits.find { |limit| Costs::LimitEvaluator.call(limit).exceeded? }
      return true unless exceeded_limit

      raise Error, "Cost limit exceeded: #{exceeded_limit.name}"
    end

    private

    def matching_limits
      tenant = @context.fetch(:tenant)
      tenant.cost_limits.enabled.where(enforcement_mode: "hard_stop").select do |limit|
        limit_matches_context?(limit)
      end
    end

    def limit_matches_context?(limit)
      return false if limit.operation_id.present? && limit.operation_id != @context[:operation]&.id

      matcher = TARGET_MATCHERS[limit.target_type]
      matcher ? send(matcher, limit) : false
    end

    def tenant_limit_matches?(_limit) = true

    def operation_limit_matches?(limit) = limit.operation_id == @context[:operation]&.id

    def user_limit_matches?(limit) = limit.target_id == @context[:user]&.id

    def agent_limit_matches?(limit) = limit.target_id == @context[:agent]&.id

    def mission_limit_matches?(limit) = limit.target_id == @context[:mission]&.id

    def channel_limit_matches?(limit) = limit.target_id == @context[:channel]&.id

    def model_limit_matches?(limit) = limit.target_id == @context[:model_id]

    def execution_context_limit_matches?(limit) = limit.target_key == @context[:execution_context].to_s
  end
end
