# frozen_string_literal: true

module Admin
  class OperationsController < BaseController
    before_action :set_operation, only: [:edit, :update, :destroy]

    def index
      authorize Operation
      @operations = scoped_operations.ordered.to_a
      Operation.preload_counts(@operations)
    end

    def new
      @operation = current_tenant.operations.new
      authorize @operation
    end

    def edit
      authorize @operation
    end

    def create
      @operation = current_tenant.operations.new(operation_params)
      authorize @operation

      if @operation.save
        redirect_to admin_operations_path, notice: t("operations.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @operation

      if @operation.update(operation_params)
        redirect_to admin_operations_path, notice: t("operations.updated")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @operation

      unless @operation.destroyable?
        redirect_to admin_operations_path, alert: t("operations.cannot_delete_system")
        return
      end

      @operation.destroy!
      # If the deleted operation was selected, fall back to default
      if session[:current_operation_id] == @operation.id
        session[:current_operation_id] = current_tenant.default_operation&.id
      end
      redirect_to admin_operations_path, notice: t("operations.deleted"), status: :see_other
    end

    def switch
      operation = scoped_operations.friendly.find(params.expect(:id))
      authorize operation, :switch?
      Operation.set_current_operation(session, operation)

      redirect_target = params[:redirect_to].presence
      if redirect_target
        redirect_to redirect_target, allow_other_host: false
      else
        redirect_back_or_to admin_root_path
      end
    end

    private

    def set_operation
      @operation = scoped_operations.friendly.find(params.expect(:id))
    end

    def operation_params
      params.expect(operation: [:name, :description])
    end
  end
end
