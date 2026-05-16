# frozen_string_literal: true

module Admin
  class AgentAlphaReferencesController < BaseController
    include AgentAlphaSupport

    def index
      return render json: { groups: [] } unless agent_alpha_configured?

      groups = ChatReferences::Search.new(
        tenant: current_tenant,
        operation: current_operation,
        kinds: agent_alpha_reference_kinds,
      ).call(query: params[:q])

      render json: { groups: }
    end
  end
end
