# frozen_string_literal: true

module LlmConfigHelper
  THINKING_EFFORT_OPTIONS = [
    ["Model default", ""],
    ["Off", "none"],
    ["Low", "low"],
    ["Medium", "medium"],
    ["High", "high"],
  ].freeze
  MODEL_ROUTING_STRATEGY_OPTIONS = [
    ["Single Model", Llm::ModelRoutingConfig::DEFAULT_STRATEGY],
    ["Fallback", "fallback"],
    ["Canary", "canary"],
    ["A/B Compare", "ab_test"],
  ].freeze

  def thinking_effort_options_for_select
    THINKING_EFFORT_OPTIONS
  end

  def model_routing_strategy_options_for_select
    MODEL_ROUTING_STRATEGY_OPTIONS
  end

  def model_routing_editor_config(value)
    Llm::ModelRoutingConfig.normalize(value)
  rescue Llm::ModelRoutingConfig::InvalidConfigError
    Llm::ModelRoutingConfig.default
  end

  def model_routing_connector_options(connectors)
    connectors.to_a.map do |connector|
      { value: connector.id.to_s, label: "#{connector.name} (#{connector.provider_label})" }
    end
  end

  def model_routing_model_catalog(connectors)
    connector_list = connectors.to_a
    providers = connector_list.filter_map { |connector| connector.provider.presence }.uniq
    models_by_provider = Model.where(provider: providers).order(:name).picker_projection.group_by(&:provider)

    connector_list.to_h do |connector|
      options = Array(models_by_provider[connector.provider]).map do |model_record|
        {
          value: model_record.model_id,
          label: model_record.name,
        }
      end

      [connector.id.to_s, options]
    end
  end

  def model_routing_editor_state(input_value:, connectors:, compact:)
    routing_config = model_routing_editor_config(input_value)
    strategy = routing_config.fetch("strategy", Llm::ModelRoutingConfig::DEFAULT_STRATEGY)

    {
      strategy:,
      fallback_routes: model_routing_fallback_routes(strategy:, routing_config:),
      canary_route: routing_config["canary_model"] || {},
      comparison_route: routing_config["comparison_model"] || {},
      connector_options: model_routing_connector_options(connectors),
      model_catalog: model_routing_model_catalog(connectors),
      container_classes: ["llm-routing-editor", ("llm-routing-editor--compact" if compact)].compact.join(" "),
      select_class: compact ? "ms-prop-select" : "form-input form-select",
      input_class: compact ? "ms-prop-input" : "form-input",
      canary_percent: routing_config["canary_percent"],
    }
  end

  def model_routing_route_state(route:, model_catalog:, options:)
    connector_id = route["connector_id"].to_s

    {
      connector_id:,
      model_id: route["model_id"].to_s,
      model_options: model_catalog.fetch(connector_id, []),
      label_prefix: options.fetch(:label_prefix),
      select_class: options.fetch(:select_class),
      wrapper_class: options.fetch(:wrapper_class),
      removable: options.fetch(:removable),
    }
  end

  def model_routing_fallback_routes(strategy:, routing_config:)
    routes = Array(routing_config["fallback_models"])
    return [{}] if strategy == "fallback" && routes.empty?

    routes
  end

  def llm_model_option_properties(model_record)
    {
      provider: model_record.provider,
      supports_temperature: model_record.supports_temperature?,
      supports_reasoning: model_record.supports_reasoning?,
    }
  end
end
