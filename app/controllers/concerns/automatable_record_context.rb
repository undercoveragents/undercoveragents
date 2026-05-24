# frozen_string_literal: true

module AutomatableRecordContext
  private

  def set_schedulable
    @schedulable = resolved_schedulable
    adopt_schedulable_operation!(@schedulable.operation)
  end

  def adopt_schedulable_operation!(operation)
    Operation.set_current_operation(session, operation)
    @current_operation = operation
    Current.operation = operation
  end

  def resolved_schedulable
    if params[:mission_id].present?
      current_tenant.missions.includes(:operation).friendly.find(params.expect(:mission_id))
    elsif params[:rag_flow_id].present?
      current_tenant.rag_flows.includes(:operation).friendly.find(params.expect(:rag_flow_id))
    else
      raise ActionController::RoutingError, "Unknown automation target"
    end
  end
end
