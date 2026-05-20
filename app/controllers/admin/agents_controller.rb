# frozen_string_literal: true

module Admin
  class AgentsController < BaseController
    include AgentDefaultAttributes
    include ModelOptionsSupport
    include Toggleable
    include AgentAssociations

    before_action :set_agent, only: [
      :show, :edit, :edit_instructions, :update, :destroy, :toggle, :restore,
      :duplicate,
      :add_tool, :remove_tool, :add_capability, :add_subagent, :remove_subagent,
      :add_skill_catalog, :remove_skill_catalog,
    ]
    def index
      authorize Agent
      ensure_builtin_agents!
      @agents = scoped_agents.ordered.to_a
      @agent_skill_counts = build_agent_skill_counts(@agents)
    end

    def show = authorize(@agent) && load_show_data

    def new
      @agent = Agent.new(default_agent_attributes(SystemPreference.current_settings(tenant: current_tenant)))
      authorize @agent
      load_form_data
    end

    def edit = authorize(@agent) && load_form_data
    def edit_instructions = authorize(@agent, :update?) && load_instruction_form_data

    def create
      @agent = Agent.new(default_agent_attributes.merge(operation: current_operation))
      apply_agent_params
      authorize @agent
      if @agent.save
        redirect_to admin_agent_path(@agent), notice: t("agents.created")
      else
        load_form_data
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @agent
      apply_agent_params
      if @agent.save
        redirect_to admin_agent_path(@agent), notice: t("agents.updated")
      else
        render_failed_update
      end
    end

    def duplicate
      authorize @agent, :duplicate?

      duplicate = @agent.dup
      duplicate.configuration = @agent.configuration.deep_dup
      duplicate.name = duplicate_name_for(@agent.operation.agents, @agent.name)
      duplicate[:builtin] = false
      duplicate.builtin = false
      duplicate.builtin_key = nil
      duplicate.builtin_source = nil

      if duplicate.save
        redirect_to admin_agent_path(duplicate), notice: t("agents.duplicated")
      else
        redirect_to admin_agent_path(@agent), alert: duplicate.errors.full_messages.to_sentence
      end
    end

    def destroy
      authorize @agent
      @agent.destroy!
      redirect_to admin_agents_path, notice: t("agents.deleted"),
                                     status: :see_other
    end

    def toggle = super
    def toggle_record = @agent
    def toggle_redirect_path = admin_agents_path
    def toggle_i18n_prefix = "agents"

    def restore
      authorize @agent, :restore?
      raise ActiveRecord::RecordNotFound, "Not a builtin agent" unless @agent.builtin?

      BuiltinAgents::Synchronizer.restore!(@agent.builtin_key, tenant: current_tenant)
      redirect_to admin_agent_path(Agent.find_builtin_by_key(@agent.builtin_key, tenant: current_tenant)),
                  notice: t("agents.restored")
    end

    def restore_defaults
      authorize Agent, :restore_defaults?
      result = BuiltinAgents::Synchronizer.restore_all!(tenant: current_tenant)
      count = result.restored_keys.size + result.created_keys.size
      redirect_to admin_agents_path, notice: t("agents.restored_all", count:)
    end

    def add_tool = super
    def remove_tool = super
    def add_capability = super
    def add_subagent = super
    def remove_subagent = super
    def add_skill_catalog = super
    def remove_skill_catalog = super

    def embedding_model_options = render_filtered_model_options(filter: :embedding)
    def image_model_options = render_filtered_model_options(filter: :image)
    def model_options = render_model_options(model_options_config)

    private

    def model_options_config
      {
        frame_id: params.require(:frame_id),
        field_prefix: params.require(:field_prefix),
        field_name: params[:field_name].presence,
        required: params[:required].present? ? params[:required] != "false" : nil,
        llm_settings: ActiveModel::Type::Boolean.new.cast(params[:llm_settings]),
      }.compact
    end

    def set_agent = @agent = current_tenant.agents.friendly.find(params.expect(:id))

    def apply_agent_params
      permitted = params.expect(
        agent: [:name, :description, :instructions, :model_id, :temperature, :enabled,
                :agent_type, :llm_config_source,
                :llm_connector_id, :thinking_effort, :thinking_budget, :custom_llm_params,
                :input_schema, :edit_context,
                { assigned_tool_ids: [], subagent_ids: [], skill_catalog_ids: [] },],
      )
      @agent.name = permitted[:name] if permitted.key?(:name)
      permitted.except(:name, :input_schema, :edit_context).each { |k, v| @agent.public_send(:"#{k}=", v) }
      @agent.input_schema = parse_input_schema(permitted[:input_schema]) if permitted.key?(:input_schema)
    end

    def build_agent_skill_counts(agents)
      catalog_ids = agents.flat_map(&:skill_catalog_ids).uniq
      return {} if catalog_ids.empty?

      skill_counts_by_catalog_id = Skill.where(skill_catalog_id: catalog_ids).group(:skill_catalog_id).count
      agents.index_with do |agent|
        agent.skill_catalog_ids.sum { |catalog_id| skill_counts_by_catalog_id.fetch(catalog_id, 0) }
      end
    end

    def load_show_data
      load_agent_association_options
      @builtin_tool_entries = builtin_tool_entries
    end

    def load_agent_association_options
      {
        available_tools: scoped_tools.where.not(id: @agent.tool_ids).ordered,
        available_agents: scoped_agents.enabled.selectable.ordered.where.not(id: [@agent.id] + @agent.subagent_ids),
        available_skill_catalogs: scoped_skill_catalogs.where.not(id: @agent.skill_catalog_ids).ordered,
      }.each { |name, value| instance_variable_set(:"@#{name}", value) }
    end

    def builtin_tool_entries
      @agent.runtime_tool_keys.map do |tool_key|
        definition = BuiltinTools::Registry.definition_for(tool_key)
        {
          key: tool_key,
          name: definition&.name || tool_key,
          description: definition&.description || "Missing built-in tool definition.",
          missing: definition.nil?,
        }
      end
    end

    def load_form_data
      @available_tools = scoped_tools.enabled.ordered
      @available_agents = scoped_agents.enabled.selectable.ordered.where.not(id: @agent.id)
      @available_llm_connectors = scoped_connectors.llm_providers.enabled.ordered
      provider_connector = @agent.llm_connector
      provider = provider_connector.provider if provider_connector&.connector_type == "llm_provider"
      @available_models = if provider.present?
                            Model.where(provider:).order(:name).picker_projection
                          else
                            Model.none
                          end
    end

    def load_instruction_form_data = @available_llm_connectors = scoped_connectors.llm_providers.enabled.ordered

    def ensure_builtin_agents!
      BuiltinAgents::Synchronizer.ensure_present!(tenant: current_tenant) if current_operation.headquarter?
    end

    def parse_input_schema(raw)
      return [] if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      []
    end

    def render_filtered_model_options(filter:)
      available_models = models_for_connector(params[:connector_id], filter:)
      locals = {
        frame_id: params.require(:frame_id),
        field_prefix: params.require(:field_prefix),
        available_models:,
        selected_model_id: params[:selected_model_id].presence,
      }
      locals[:field_name] = params[:field_name] if params[:field_name].present?
      render partial: "shared/model_select", locals:
    end

    def render_failed_update
      case params.dig(:agent, :edit_context)
      when "instructions"
        load_instruction_form_data
        render :edit_instructions, status: :unprocessable_content
      when "input_parameters"
        load_show_data
        render :show, status: :unprocessable_content
      else
        load_form_data
        render :edit, status: :unprocessable_content
      end
    end
  end
end
