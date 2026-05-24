# frozen_string_literal: true

# Extracted from AgentsController — handles adding/removing tools, capabilities, and sub-agents.
module AgentAssociations
  extend ActiveSupport::Concern

  def add_tool
    authorize @agent, :update?

    case params[:tool_ref].to_s
    when /\Atool:(.+)\z/
      add_persisted_tool(::Regexp.last_match(1))
    when /\Aruntime_tool:(.+)\z/
      add_runtime_tool_key(::Regexp.last_match(1))
    else
      if params[:runtime_tool_key].present?
        add_runtime_tool_key(params.expect(:runtime_tool_key))
      else
        add_persisted_tool(params.expect(:tool_id))
      end
    end

    @agent.save!
    redirect_to admin_agent_path(@agent), notice: t("agents.tool_added")
  end

  def remove_tool
    authorize @agent, :update?

    if params[:runtime_tool_key].present?
      remove_runtime_tool_key(params.expect(:runtime_tool_key))
    else
      @agent.tool_ids = @agent.tool_ids - [params.expect(:tool_id).to_i]
    end

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

  private

  def add_persisted_tool(tool_id)
    tool = scoped_tools.find(tool_id)
    @agent.tool_ids = (@agent.tool_ids + [tool.id]).uniq
  end

  def add_runtime_tool_key(tool_key)
    return if @agent.builtin?

    normalized_tool_key = tool_key.to_s
    unless BuiltinTools::Registry.user_assignable_keys.include?(normalized_tool_key)
      raise ActiveRecord::RecordNotFound, "Unknown built-in tool"
    end

    @agent.runtime_tool_keys = (@agent.runtime_tool_keys + [normalized_tool_key]).uniq
  end

  def remove_runtime_tool_key(tool_key)
    return if @agent.builtin?

    @agent.runtime_tool_keys = @agent.runtime_tool_keys - [tool_key.to_s]
  end
end
