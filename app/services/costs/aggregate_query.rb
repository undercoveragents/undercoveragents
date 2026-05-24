# frozen_string_literal: true

module Costs
  class AggregateQuery
    Summary = Data.define(
      :total_cost,
      :input_tokens,
      :output_tokens,
      :message_count,
      :chat_count,
      :average_chat_cost,
    )
    Group = Data.define(:key, :label, :cost, :input_tokens, :output_tokens, :message_count, :chat_count)
    DIMENSION_METHODS = {
      "operation" => :operation_dimension_key,
      "user" => :user_dimension_key,
      "agent" => :agent_dimension_key,
      "mission" => :mission_dimension_key,
      "channel" => :channel_dimension_key,
      "model" => :model_dimension_key,
      "execution_context" => :execution_context_dimension_key,
    }.freeze

    def initialize(message_scope)
      @message_scope = message_scope
    end

    def summary
      records = messages
      cost = total_cost(records)
      chat_count = records.map(&:chat_id).uniq.size

      Summary.new(
        total_cost: cost,
        input_tokens: records.sum(&:total_input_activity_tokens),
        output_tokens: records.sum { |message| message.output_tokens.to_i },
        message_count: records.size,
        chat_count:,
        average_chat_cost: chat_count.positive? ? cost / chat_count : BigDecimal("0"),
      )
    end

    def by_dimension(dimension, limit: 8)
      grouped = messages.group_by { |message| dimension_key(message, dimension) }
      grouped.filter_map { |key, records| build_group(key, records, dimension) }
             .sort_by { |group| -group.cost }
             .first(limit)
    end

    def cost_by_day
      messages.group_by { |message| message.created_at.to_date }
              .transform_values { |records| total_cost(records) }
              .sort
              .to_h
    end

    private

    def messages
      @messages ||= @message_scope.includes(:model, chat: [:operation, :user, :agent, :mission, :channel, :model]).to_a
    end

    def build_group(key, records, _dimension)
      return if key.blank?

      Group.new(
        key: key.first,
        label: key.second,
        cost: total_cost(records),
        input_tokens: records.sum(&:total_input_activity_tokens),
        output_tokens: records.sum { |message| message.output_tokens.to_i },
        message_count: records.size,
        chat_count: records.map(&:chat_id).uniq.size,
      )
    end

    def total_cost(records)
      records.sum(&:effective_cost)
    end

    def dimension_key(message, dimension)
      method_name = DIMENSION_METHODS[dimension.to_s]
      send(method_name, message) if method_name
    end

    def operation_dimension_key(message) = record_key(message.chat.operation)

    def user_dimension_key(message) = record_key(message.chat.user, label_method: :email)

    def agent_dimension_key(message) = record_key(message.chat.agent)

    def mission_dimension_key(message) = record_key(message.chat.mission)

    def channel_dimension_key(message) = record_key(message.chat.channel)

    def model_dimension_key(message) = record_key(message.model || message.chat.model, label_method: :model_id)

    def execution_context_dimension_key(message)
      [message.chat.execution_context, message.chat.execution_context.humanize]
    end

    def record_key(record, label_method: :name)
      return unless record

      [record.id, record.public_send(label_method)]
    end
  end
end
