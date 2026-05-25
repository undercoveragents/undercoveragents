# frozen_string_literal: true

module Admin
  class CostsController < BaseController
    def show
      authorize CostLimit, :index?
      load_filter_state
      @presenter = CostAnalysisPresenter.new(
        tenant: current_tenant,
        operation: @selected_operation,
        period: @period,
        filters: presenter_filters,
      )
    end

    private

    def selected_operation
      return if params[:operation].blank? || params[:operation] == "all"

      scoped_operations.friendly.find(params.expect(:operation))
    end

    def selected_period
      period = params[:period].presence || "rolling_30_days"
      CostLimit::PERIODS.include?(period) ? period : "rolling_30_days"
    end

    def load_filter_state
      @operations = scoped_operations.headquarter_first
      @selected_operation = selected_operation
      @period = selected_period
      @selected_execution_context = selected_execution_context
      @selected_user = selected_user
      @selected_agent = selected_agent
      @selected_model = selected_model
      @execution_context_options = Chat.execution_contexts.keys.map { |context| [context.humanize, context] }
      @user_options = user_filter_scope
      @agent_options = agent_filter_scope
      @model_options = model_filter_scope
    end

    def presenter_filters
      CostAnalysisPresenter::FilterSet.new(
        execution_context: @selected_execution_context,
        user: @selected_user,
        agent: @selected_agent,
        model: @selected_model,
      )
    end

    def selected_execution_context
      value = params[:execution_context].presence
      return if value.blank? || value == "all"

      Chat.execution_contexts.key?(value) ? value : nil
    end

    def selected_user
      selected_record_from(user_filter_scope, :user_id)
    end

    def selected_agent
      selected_record_from(agent_filter_scope, :agent_id)
    end

    def selected_model
      selected_record_from(model_filter_scope, :model_id)
    end

    def selected_record_from(scope, param_key)
      value = params[param_key].presence
      return if value.blank? || value == "all"

      scope.find_by(id: value)
    end

    def user_filter_scope
      @user_filter_scope ||= current_tenant.users.order(:email)
    end

    def agent_filter_scope
      @agent_filter_scope ||= begin
        scope = if @selected_operation
                  Agent.where(operation: @selected_operation)
                else
                  Agent.joins(:operation).where(operations: { tenant_id: current_tenant.id })
                end

        scope.order(:name)
      end
    end

    def model_filter_scope
      @model_filter_scope ||= begin
        model_ids = chat_model_ids + message_model_ids
        Model.where(id: model_ids.uniq).order(:model_id)
      end
    end

    def chat_model_ids
      scoped_chat_models.where.not(model_id: nil).distinct.pluck(:model_id)
    end

    def message_model_ids
      scoped_message_models.where.not(model_id: nil).distinct.pluck(:model_id)
    end

    def scoped_chat_models
      scope = Chat.where(tenant_id: current_tenant.id)
      scope = scope.where(operation_id: @selected_operation.id) if @selected_operation
      scope
    end

    def scoped_message_models
      scope = Message.joins(:chat).where(chats: { tenant_id: current_tenant.id })
      scope = scope.where(chats: { operation_id: @selected_operation.id }) if @selected_operation
      scope
    end
  end
end
