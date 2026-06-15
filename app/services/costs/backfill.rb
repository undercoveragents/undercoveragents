# frozen_string_literal: true

module Costs
  class Backfill
    Result = Data.define(:processed_chats, :updated_chats, :processed_messages, :updated_messages)

    def self.call(say: nil)
      new(say:).call
    end

    def initialize(say: nil)
      @say = say || ->(_message) {}
    end

    def call
      updated_chats = backfill_chats
      updated_messages = backfill_messages

      Result.new(
        processed_chats:,
        updated_chats:,
        processed_messages:,
        updated_messages:,
      )
    end

    private

    attr_reader :say

    def processed_chats = @processed_chats ||= 0

    def processed_messages = @processed_messages ||= 0

    def backfill_chats
      say.call("Backfilling chat tenant/operation attribution")
      updated_chats = 0

      chat_scope.find_each do |chat|
        @processed_chats = processed_chats + 1
        updated_chats += 1 if update_chat_attribution(chat)
      end

      say.call("Updated #{updated_chats} chats")
      updated_chats
    end

    def backfill_messages
      say.call("Backfilling message cost snapshots")
      updated_messages = 0

      message_scope.find_each do |message|
        @processed_messages = processed_messages + 1
        updated_messages += 1 if update_message_snapshot(message)
      end

      say.call("Updated #{updated_messages} messages")
      updated_messages
    end

    def chat_scope
      Chat.where(tenant_id: nil).or(Chat.where(operation_id: nil))
    end

    def message_scope
      Message.includes(:model, chat: :model)
             .where(cost_usd: nil)
             .or(Message.where(cost_calculated_at: nil))
             .or(Message.where(cost_pricing_snapshot: {}))
    end

    def update_chat_attribution(chat)
      chat.send(:assign_cost_attribution)
      attributes = changed_chat_attributes(chat)
      return false if attributes.empty?

      chat.update_columns(attributes.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    end

    def changed_chat_attributes(chat)
      {}.tap do |attributes|
        attributes[:tenant_id] = chat.tenant_id if chat.will_save_change_to_tenant_id?
        attributes[:operation_id] = chat.operation_id if chat.will_save_change_to_operation_id?
      end
    end

    def update_message_snapshot(message)
      Costs::MessageCostSnapshotter.call(message)
      return false unless message.changed?

      message.save!
    end
  end
end
