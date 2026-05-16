# frozen_string_literal: true

module Admin
  # Handles editing and updating individual capability configurations for an agent.
  #
  # Capabilities live at:
  #   GET  /agents/:agent_id/capabilities/:key/edit
  #   PATCH /agents/:agent_id/capabilities/:key
  #
  # The :key param is the capability key symbol (e.g. "title_generator").
  # Each capability type is self-contained: it defines +self.permitted_params+
  # and validation rules through its plugin configurator.
  #
  class CapabilitiesController < BaseController
    before_action :set_agent
    before_action :set_capability

    def edit
      authorize @agent, :update?
      load_form_data
    end

    def update
      authorize @agent, :update?

      raw = params.require(:capability)
      attrs = @capability_type.permitted_params(raw)

      configurator = @capability_type.new
      configurator._agent_record = @agent if configurator.respond_to?(:_agent_record=)
      configurator.assign_attributes(attrs.to_h)

      if configurator.valid?
        save_capability(configurator)
      else
        render_capability_errors(configurator)
      end
    end

    def destroy
      authorize @agent, :update?
      @agent.remove_capability_config(@capability_key)
      @agent.save!
      redirect_to admin_agent_path(@agent), notice: t("capabilities.removed"), status: :see_other
    end

    private

    def set_agent
      @agent = scoped_agents.friendly.find(params.expect(:agent_id))
    end

    def save_capability(configurator)
      @agent.set_capability_config(@capability_key, configurator.to_configuration)

      if @agent.save
        notify_capability_enabled(configurator)
        redirect_to admin_agent_path(@agent), notice: t("capabilities.updated")
      else
        render_capability_errors(configurator)
      end
    end

    def render_capability_errors(configurator)
      configurator._agent_record = @agent if configurator.respond_to?(:_agent_record=)
      @capability_config = configurator
      load_form_data
      render :edit, status: :unprocessable_content
    end

    def set_capability
      @capability_key  = params.expect(:key).to_sym
      @capability_type = CapabilityPlugin.resolve(@capability_key)
      raise ActionController::RoutingError, "Unknown capability: #{params[:key]}" unless @capability_type

      @capability_type_label = @capability_type.label

      stored_config = stored_capability_config
      @capability_config = @agent.capability(@capability_key) || @capability_type.new
      @capability_assigned = stored_config.present?
    end

    def load_form_data
      @available_llm_connectors = scoped_connectors.llm_providers.enabled.ordered
    end

    def stored_capability_config
      return unless @agent.configuration.is_a?(Hash)

      @agent.configuration.fetch("capabilities", {})[@capability_key.to_s]
    end

    # Duck-typed callback: if the configurator implements after_capability_enabled,
    # call it after a successful save when the capability is enabled.
    def notify_capability_enabled(configurator)
      return unless configurator.respond_to?(:after_capability_enabled)

      configurator.after_capability_enabled(@agent)
    rescue StandardError => e
      Rails.logger.error "[CapabilitiesController] after_capability_enabled failed: #{e.message}"
    end
  end
end
