# frozen_string_literal: true

module Admin
  module Inspector
    class ChatsController < BaseController
      before_action :set_chat, only: [:show]

      def index
        base_scope = tenant_scoped_chats
        base_scope = filter_by_operation(base_scope)
        @q = base_scope.ransack(permitted_q_params)
        @pagy, @chats = pagy(:offset, @q.result.includes({ agent: :operation }, :model).recent, limit: 50)
        @filter_options = build_filter_options
      end

      def show
        @messages = load_messages
        @child_chats = load_child_chats
        @child_messages = load_child_messages(@child_chats)
        @child_chat_metrics = build_child_chat_metrics(@child_messages)
        @total_cost = compute_total_cost_with_children
        @message_counts = compute_message_counts(@messages)
        @token_totals = compute_token_totals_with_children
      end

      private

      def set_chat
        @chat = tenant_scoped_chats.includes(:agent, :model, :parent_chat, :user).find(params.expect(:id))
      end

      def permitted_q_params
        return {} if params[:q].blank?

        params.expect(q: [:id_eq,
                          :title_cont,
                          :execution_context_eq,
                          :agent_id_eq,
                          :model_id_eq,
                          :parent_chat_id_null,
                          :parent_chat_id_not_null,
                          :s,])
      end

      def build_filter_options
        {
          execution_contexts: Chat.execution_contexts.keys,
          agents: scoped_agents.order(:name).pluck(:name, :id),
          models: Model.order(:model_id).pluck(:model_id, :id).uniq(&:first),
          operations: scoped_operations.ordered.pluck(:name, :slug),
        }
      end

      def filter_by_operation(scope)
        return scope if params[:operation].blank?

        op = scoped_operations.friendly.find(params.expect(:operation))
        scope.where(agent_id: Agent.where(operation: op).select(:id))
      end

      def load_messages
        @chat.messages
             .includes(:model, :chat, :tool_calls)
             .order(:created_at)
      end

      def load_child_chats
        @chat.child_chats
             .includes(:agent, :model)
             .order(created_at: :asc)
             .to_a
      end

      def load_child_messages(child_chats)
        return [] if child_chats.empty?

        Message.where(chat_id: child_chats.map(&:id))
               .includes(:model, :chat)
               .order(:created_at)
               .to_a
      end

      def build_child_chat_metrics(messages)
        messages.group_by(&:chat_id).transform_values do |chat_messages|
          {
            cost: chat_messages.sum(&:effective_cost),
            tokens: {
              input: chat_messages.sum(&:total_input_activity_tokens),
              output: chat_messages.sum { |m| m.output_tokens.to_i },
            },
          }
        end
      end

      def compute_message_counts(messages)
        {
          total: messages.size,
          user: messages.count(&:user?),
          assistant: messages.count(&:assistant?),
          system: messages.count(&:system?),
          tool: messages.count(&:tool?),
        }
      end

      def compute_token_totals(messages)
        {
          input: messages.sum { |m| m.input_tokens.to_i },
          output: messages.sum { |m| m.output_tokens.to_i },
          cached: messages.sum { |m| m.cached_tokens.to_i },
          cache_creation: messages.sum { |m| m.cache_creation_tokens.to_i },
          thinking: messages.sum { |m| m.thinking_tokens.to_i },
        }
      end

      def compute_total_cost_with_children
        own_cost = @messages.sum(&:effective_cost)
        children_cost = @child_chat_metrics.values.sum { |metrics| metrics[:cost] }
        own_cost + children_cost
      end

      def compute_token_totals_with_children
        own_totals = compute_token_totals(@messages)
        child_totals = compute_token_totals(@child_messages)

        own_totals.merge(child_totals) { |_key, own, child| own + child }
      end
    end
  end
end
