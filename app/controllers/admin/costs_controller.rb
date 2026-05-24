# frozen_string_literal: true

module Admin
  class CostsController < BaseController
    def show
      authorize CostLimit, :index?
      @operations = scoped_operations.headquarter_first
      @selected_operation = selected_operation
      @period = selected_period
      @presenter = CostAnalysisPresenter.new(
        tenant: current_tenant,
        operation: @selected_operation,
        period: @period,
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
  end
end
