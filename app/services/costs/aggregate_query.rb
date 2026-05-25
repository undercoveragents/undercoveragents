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
    PERSISTED_COST_SQL = "COALESCE(messages.cost_usd, 0)"
    DIMENSION_DEFINITIONS = {
      "operation" => {
        apply: ->(scope) { scope.left_outer_joins(chat: :operation) },
        key_sql: Arel.sql("chats.operation_id"),
        label_sql: Arel.sql("operations.name"),
        presence_sql: Arel.sql("chats.operation_id IS NOT NULL"),
      },
      "user" => {
        apply: ->(scope) { scope.left_outer_joins(chat: :user) },
        key_sql: Arel.sql("chats.user_id"),
        label_sql: Arel.sql("users.email"),
        presence_sql: Arel.sql("chats.user_id IS NOT NULL"),
      },
      "agent" => {
        apply: ->(scope) { scope.left_outer_joins(chat: :agent) },
        key_sql: Arel.sql("chats.agent_id"),
        label_sql: Arel.sql("agents.name"),
        presence_sql: Arel.sql("chats.agent_id IS NOT NULL"),
      },
      "mission" => {
        apply: ->(scope) { scope.left_outer_joins(chat: :mission) },
        key_sql: Arel.sql("chats.mission_id"),
        label_sql: Arel.sql("missions.name"),
        presence_sql: Arel.sql("chats.mission_id IS NOT NULL"),
      },
      "channel" => {
        apply: ->(scope) { scope.left_outer_joins(chat: :channel) },
        key_sql: Arel.sql("chats.channel_id"),
        label_sql: Arel.sql("channels.name"),
        presence_sql: Arel.sql("chats.channel_id IS NOT NULL"),
      },
      "model" => {
        apply: lambda do |scope|
          scope.joins(<<~SQL.squish)
            LEFT JOIN models AS message_models ON message_models.id = messages.model_id
            LEFT JOIN models AS chat_models ON chat_models.id = chats.model_id
          SQL
        end,
        key_sql: Arel.sql("COALESCE(messages.model_id, chats.model_id)"),
        label_sql: Arel.sql("COALESCE(message_models.model_id, chat_models.model_id)"),
        presence_sql: Arel.sql("COALESCE(messages.model_id, chats.model_id) IS NOT NULL"),
      },
      "execution_context" => {
        apply: ->(scope) { scope },
        key_sql: Arel.sql("chats.execution_context"),
        label_sql: Arel.sql("INITCAP(REPLACE(chats.execution_context, '_', ' '))"),
        presence_sql: Arel.sql("chats.execution_context IS NOT NULL"),
      },
    }.freeze

    def initialize(message_scope)
      @aggregate_scope = message_scope.where.not(cost_usd: nil).reorder(nil)
    end

    def summary
      total_cost, input_tokens, output_tokens, message_count, chat_count = @aggregate_scope.pick(
        total_cost_sum_sql,
        sum_input_activity_sql,
        sum_output_tokens_sql,
        count_all_sql,
        count_distinct_chat_sql,
      )
      chat_count = chat_count.to_i

      Summary.new(
        total_cost: decimal(total_cost),
        input_tokens: input_tokens.to_i,
        output_tokens: output_tokens.to_i,
        message_count: message_count.to_i,
        chat_count:,
        average_chat_cost: chat_count.positive? ? decimal(total_cost) / chat_count : BigDecimal("0"),
      )
    end

    def by_dimension(dimension, limit: 8)
      config = DIMENSION_DEFINITIONS[dimension.to_s]
      return [] unless config

      grouped_rows(config, limit)
    end

    def cost_by_day
      @aggregate_scope.group_by_day(:created_at, series: false)
                      .sum(cost_expression_sql)
                      .transform_values { |value| decimal(value) }
    end

    private

    def grouped_rows(config, limit)
      relation = config.fetch(:apply).call(@aggregate_scope)
      grouped_row_data(relation, config, limit).map { |row| build_group(row) }
    end

    def grouped_row_data(relation, config, limit)
      relation.where(config.fetch(:presence_sql))
              .group(config.fetch(:key_sql), config.fetch(:label_sql))
              .order(total_cost_order_sql)
              .limit(limit)
              .pluck(*grouped_row_selects(config))
    end

    def grouped_row_selects(config)
      [
        config.fetch(:key_sql),
        config.fetch(:label_sql),
        total_cost_sum_sql,
        sum_input_activity_sql,
        sum_output_tokens_sql,
        count_all_sql,
        count_distinct_chat_sql,
      ]
    end

    def build_group(row)
      key, label, cost, input_tokens, output_tokens, message_count, chat_count = row

      Group.new(
        key:,
        label:,
        cost: decimal(cost),
        input_tokens: input_tokens.to_i,
        output_tokens: output_tokens.to_i,
        message_count: message_count.to_i,
        chat_count: chat_count.to_i,
      )
    end

    def total_cost_sum_sql = Arel.sql("COALESCE(SUM(#{PERSISTED_COST_SQL}), 0)")

    def sum_input_activity_sql = Arel.sql("COALESCE(SUM(#{Message::TOTAL_INPUT_ACTIVITY_SQL}), 0)")

    def sum_output_tokens_sql = Arel.sql("COALESCE(SUM(COALESCE(messages.output_tokens, 0)), 0)")

    def count_all_sql = Arel.sql("COUNT(*)")

    def count_distinct_chat_sql = Arel.sql("COUNT(DISTINCT messages.chat_id)")

    def total_cost_order_sql = Arel.sql("SUM(#{PERSISTED_COST_SQL}) DESC")

    def cost_expression_sql = Arel.sql(PERSISTED_COST_SQL)

    def decimal(value) = BigDecimal(value.to_s.presence || "0")
  end
end
