# frozen_string_literal: true

module Admin
  class AgentPromptPreviewsController < BaseController
    before_action :set_agent

    def show
      authorize @agent, :show?
      @preview = Agents::PromptPreview.new(@agent, user: current_user).call
      render "agents/prompt_preview"
    end

    private

    def set_agent = @agent = current_tenant.agents.friendly.find(params.expect(:id))
  end
end
