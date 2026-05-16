# frozen_string_literal: true

module AgentAlphaHelper
  def agent_alpha_page_context_token
    return unless current_user.present? && request.path.start_with?("/admin")

    AgentAlpha::PageContext.issue_for(controller)
  end
end
