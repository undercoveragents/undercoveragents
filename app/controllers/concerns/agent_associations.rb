# frozen_string_literal: true

# Extracted from AgentsController — handles adding/removing tools, capabilities, and sub-agents.
module AgentAssociations
  extend ActiveSupport::Concern

  def add_tool
    authorize @agent, :update?
    tool = scoped_tools.find(params.expect(:tool_id))
    @agent.tool_ids = (@agent.tool_ids + [tool.id]).uniq
    @agent.save!
    redirect_to admin_agent_path(@agent), notice: t("agents.tool_added")
  end

  def remove_tool
    authorize @agent, :update?
    @agent.tool_ids = @agent.tool_ids - [params.expect(:tool_id).to_i]
    @agent.save!
    redirect_to admin_agent_path(@agent), notice: t("agents.tool_removed"), status: :see_other
  end

  def add_capability
    authorize @agent, :update?
    capability_key = params.require(:key)
    unless CapabilityPlugin.resolve(capability_key)
      raise ActionController::RoutingError, "Unknown capability: #{capability_key}"
    end

    redirect_to edit_admin_agent_capability_path(@agent, capability_key)
  end

  def add_subagent
    authorize @agent, :update?
    sub = scoped_agents.friendly.find(params.expect(:subagent_id))
    @agent.subagent_ids = (@agent.subagent_ids + [sub.id]).uniq
    if @agent.save
      redirect_to admin_agent_path(@agent), notice: t("agents.subagent_added")
    else
      load_show_data
      flash.now[:alert] = @agent.errors.full_messages.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  def remove_subagent
    authorize @agent, :update?
    @agent.subagent_ids = @agent.subagent_ids - [params.expect(:subagent_id).to_i]
    @agent.save!
    redirect_to admin_agent_path(@agent), notice: t("agents.subagent_removed"), status: :see_other
  end

  def add_skill_catalog
    authorize @agent, :update?
    skill_catalog = scoped_skill_catalogs.find(params.expect(:skill_catalog_id))
    @agent.skill_catalog_ids = (@agent.skill_catalog_ids + [skill_catalog.id]).uniq
    @agent.save!
    redirect_to admin_agent_path(@agent), notice: t("agents.skill_catalog_added")
  end

  def remove_skill_catalog
    authorize @agent, :update?
    @agent.skill_catalog_ids = @agent.skill_catalog_ids - [params.expect(:skill_catalog_id).to_i]
    @agent.save!
    redirect_to admin_agent_path(@agent), notice: t("agents.skill_catalog_removed"), status: :see_other
  end
end
