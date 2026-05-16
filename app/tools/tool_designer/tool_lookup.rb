# frozen_string_literal: true

module ToolDesigner
  module ToolLookup
    private

    def resolve_tool(tool_id)
      return @current_tool if tool_id.blank? && @current_tool.is_a?(Tool)

      identifier = tool_id.to_s.strip
      return nil if identifier.blank?

      scope = tool_scope
      scope.find_by(id: identifier) || scope.find_by(slug: identifier) || missing_record!(identifier)
    end

    def missing_record!(identifier)
      raise ActiveRecord::RecordNotFound, "Tool '#{identifier}' was not found."
    end

    def tool_scope
      scope = Tool.includes(:operation)
      scope = scope.where(operation:) if operation
      scope = scope.joins(:operation).where(operations: { tenant_id: tenant.id }) if operation.nil? && tenant
      scope.ordered
    end

    def missing_tool_message
      "No current tool is available. Pass tool_id after creating one or open a tool page first."
    end

    def tenant
      @runtime_context&.tenant || @current_tool&.operation&.tenant || Current.tenant || Tenant.default_tenant
    end

    def operation
      @runtime_context&.operation || @current_tool&.operation
    end
  end
end
