# frozen_string_literal: true

module Admin
  class CostLimitsController < BaseController
    before_action :set_cost_limit, only: [:show, :edit, :update, :destroy, :toggle]
    before_action :set_form_collections, only: [:new, :edit, :create, :update]

    def index
      authorize CostLimit
      @cost_limits = scoped_cost_limits.ordered.includes(:operation)
      @limit_results = @cost_limits.map { |limit| Costs::LimitEvaluator.call(limit) }
    end

    def show
      authorize @cost_limit
      @limit_result = Costs::LimitEvaluator.call(@cost_limit)
      @recent_messages = recent_messages_for(@cost_limit)
    end

    def new
      @cost_limit = scoped_cost_limits.new(default_cost_limit_attributes)
      authorize @cost_limit
    end

    def edit
      authorize @cost_limit
    end

    def create
      @cost_limit = scoped_cost_limits.new(cost_limit_params)
      authorize @cost_limit

      if @cost_limit.save
        redirect_to admin_cost_limit_path(@cost_limit), notice: t("cost_limits.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @cost_limit

      if @cost_limit.update(cost_limit_params)
        redirect_to admin_cost_limit_path(@cost_limit), notice: t("cost_limits.updated")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @cost_limit
      @cost_limit.destroy!
      redirect_to admin_cost_limits_path, notice: t("cost_limits.deleted"), status: :see_other
    end

    def toggle
      authorize @cost_limit
      @cost_limit.update!(enabled: !@cost_limit.enabled?)
      redirect_back_or_to admin_cost_limits_path,
                          notice: t("cost_limits.toggled", state: @cost_limit.enabled? ? "enabled" : "disabled")
    end

    private

    def set_cost_limit
      @cost_limit = scoped_cost_limits.find(params.expect(:id))
    end

    def cost_limit_params
      params.expect(
        cost_limit: [
          :name,
          :description,
          :target_type,
          :target_id,
          :target_key,
          :operation_id,
          :period,
          :amount_usd,
          :warning_threshold_percent,
          :enforcement_mode,
          :enabled,
        ],
      ).to_h.transform_values(&:presence)
    end

    def default_cost_limit_attributes
      {
        target_type: "tenant",
        period: "month",
        warning_threshold_percent: 80,
        enforcement_mode: "warn_only",
        enabled: true,
      }
    end

    def set_form_collections
      @operation_options = scoped_operations.headquarter_first.pluck(:name, :id)
      @user_options = current_tenant.users.order(:email).pluck(:email, :id)
      @agent_options = current_tenant.agents.order(:name).pluck(:name, :id)
      @mission_options = current_tenant.missions.order(:name).pluck(:name, :id)
      @channel_options = current_tenant.channels.order(:name).pluck(:name, :id)
      @model_options = Model.order(:provider, :model_id).pluck(:model_id, :id)
    end

    def recent_messages_for(limit)
      Costs::Scope.new(tenant: current_tenant)
                  .for_limit(limit)
                  .includes(:chat, :model)
                  .order(Arel.sql("COALESCE(messages.cost_usd, 0) DESC"), created_at: :desc)
                  .limit(10)
    end
  end
end
