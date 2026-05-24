# frozen_string_literal: true

module Costs
  class Scope
    LIMIT_TARGET_HANDLERS = {
      "tenant" => :tenant_limit_scope,
      "operation" => :operation_limit_scope,
      "user" => :user_limit_scope,
      "agent" => :agent_limit_scope,
      "mission" => :mission_limit_scope,
      "channel" => :channel_limit_scope,
      "execution_context" => :execution_context_limit_scope,
      "model" => :model_limit_scope,
    }.freeze

    attr_reader :tenant, :operation, :range

    def initialize(tenant:, operation: nil, range: nil)
      @tenant = tenant
      @operation = operation
      @range = range
    end

    def chats
      scoped = tenant_chats
      scoped = scoped.where(operation:) if operation
      scoped = scoped.where(created_at: range) if range
      scoped
    end

    def messages
      scoped = Message.joins(:chat).where(chats: { id: chats.select(:id) })
      scoped = scoped.where(messages: { created_at: range }) if range
      scoped
    end

    def for_limit(limit)
      self.class.new(
        tenant: limit.tenant,
        operation: limit.operation,
        range: Costs::Period.resolve(limit.period).range,
      ).messages.then { |relation| apply_limit_target(relation, limit) }
    end

    private

    def tenant_chats
      direct = Chat.where(tenant_id: tenant.id)
      fallback = Chat.where(user_id: tenant.users.select(:id))
                     .or(Chat.where(agent_id: tenant.agents.select(:id)))
                     .or(Chat.where(mission_id: tenant.missions.select(:id)))

      direct.or(fallback)
    end

    def apply_limit_target(relation, limit)
      handler = LIMIT_TARGET_HANDLERS[limit.target_type]
      handler ? send(handler, relation, limit) : relation.none
    end

    def tenant_limit_scope(relation, _limit) = relation

    def operation_limit_scope(relation, limit) = relation.where(chats: { operation_id: limit.operation_id })

    def user_limit_scope(relation, limit) = relation.where(chats: { user_id: limit.target_id })

    def agent_limit_scope(relation, limit) = relation.where(chats: { agent_id: limit.target_id })

    def mission_limit_scope(relation, limit) = relation.where(chats: { mission_id: limit.target_id })

    def channel_limit_scope(relation, limit) = relation.where(chats: { channel_id: limit.target_id })

    def execution_context_limit_scope(relation, limit) = relation.where(chats: { execution_context: limit.target_key })

    def model_limit_scope(relation, limit)
      relation.where("messages.model_id = :id OR chats.model_id = :id", id: limit.target_id)
    end
  end
end
