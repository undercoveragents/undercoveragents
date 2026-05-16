# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def show
      reset_operation_selection_on_direct_entry
      @operations = scoped_operations.headquarter_first
      @selected_operation = selected_operation_for_dashboard
      @selected_operation_icon = ToolCalls::Presentation.sanitize_icon(@selected_operation&.icon) ||
                                 "fa-solid fa-layer-group"
      @presenter = DashboardPresenter.new(tenant: current_tenant, operation: @selected_operation)
      @show_getting_started = @presenter.show_getting_started
    end

    private

    def reset_operation_selection_on_direct_entry
      return if params[:operation].present?
      return if request.referer.to_s.match?(ADMIN_REFERER_PATTERN)
      return unless current_tenant

      operation = current_tenant.default_operation
      Operation.set_current_operation(session, operation)
      @current_operation = operation
      Current.operation = operation
    end

    def selected_operation_for_dashboard
      return if params[:operation] == "all"
      return scoped_operations.friendly.find(params.expect(:operation)) if params[:operation].present?
      return current_operation if request.referer.to_s.match?(ADMIN_REFERER_PATTERN)

      nil
    end
  end
end
