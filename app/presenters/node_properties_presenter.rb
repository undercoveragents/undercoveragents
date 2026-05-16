# frozen_string_literal: true

class NodePropertiesPresenter
  include NodePropertiesVariables

  ICON_CLASS_PATTERN = /\A[a-z0-9\-\s]+\z/i
  HEX_COLOR_PATTERN = /\A#(?:\h{3}|\h{6})\z/i

  attr_reader :mission, :node, :node_id, :node_type, :node_data,
              :node_metadata,
              :validation_errors

  def initialize(mission:, node_id:)
    @mission = mission
    @node_id = node_id
    @node = find_node
    @node_type = @node&.dig("type")
    @node_data = @node&.dig("data") || {}
    @node_metadata = resolve_metadata
    @validation_errors = compute_validation_errors
  end

  def found? = @node.present?
  def node_label = node_data["label"].presence || node_type
  def node_type_label = node_metadata[:label] || node_type&.titleize || "Unknown"
  def node_description = node_data["description"].presence || ""
  def node_icon = sanitize_icon_class(node_data["icon"].presence || node_metadata[:icon] || "fa-solid fa-circle")
  def node_color = sanitize_hex_color(node_data["color"].presence || node_metadata[:color] || "#6366f1")
  def config_fields? = node_type.present? && node_klass.present?
  def valid? = validation_errors.blank?

  def validation_message
    return "" if valid?

    validation_errors.map do |e|
      field = (e[:field] || e["field"]).to_s.tr("_", " ").strip
      message = (e[:message] || e["message"]).to_s
      "#{field}: #{message}"
    end.compact_blank.join("; ")
  end

  def variable_name
    derive_node_name
  end

  def data(key, default = "")
    node_data[key.to_s].presence || default
  end

  def data_raw(key) = node_data[key.to_s]
  def temperature = node_data["temperature"] || 0.7
  def llm_config_source = Missions::LlmNodeRuntimeConfig.source_for(node_data)
  def llm_config_source_node? = llm_config_source == Missions::LlmNodeRuntimeConfig::NODE_SOURCE

  def llm_config_source_options
    [
      ["Node Configuration", Missions::LlmNodeRuntimeConfig::NODE_SOURCE],
      ["System Preference", Missions::LlmNodeRuntimeConfig::SYSTEM_SOURCE],
      ["Runtime Supplied", Missions::LlmNodeRuntimeConfig::RUNTIME_SOURCE],
    ]
  end

  def cases = node_data["cases"] || {}
  def assignments = node_data["assignments"] || {}
  def extractions = node_data["extractions"] || {}
  def fields = node_data["fields"] || []
  def selected_variables = node_data["selected_variables"] || []
  def code_output_variables = node_data["output_variables"] || []

  def headers_value
    h = node_data["headers"]
    case h
    when Hash then JSON.pretty_generate(h)
    else h.to_s
    end
  end

  def http_params = http_hash_config("params")
  def http_headers = http_hash_config("headers")
  def http_form_urlencoded_body = http_hash_config("form_urlencoded_body")
  def http_multipart_form_data = http_hash_config("multipart_form_data")

  def http_auth_type
    auth_type = node_data["auth_type"].presence
    auth_type.in?(Missions::Nodes::HttpRequest::ALLOWED_AUTH_TYPES) ? auth_type : "none"
  end

  def http_body_mode
    body_mode = node_data["body_mode"].presence
    body_mode.in?(Missions::Nodes::HttpRequest::BODY_MODES) ? body_mode : "none"
  end

  def http_verify_ssl?
    boolean_http_setting(node_data.key?("verify_ssl") ? node_data["verify_ssl"] : true)
  end

  def http_retry_enabled?
    boolean_http_setting(node_data.key?("retry_enabled") ? node_data["retry_enabled"] : false)
  end

  def http_file_reference_options
    upstream_file_variables.map do |var|
      { label: var[:name], value: "{{#{var[:name]}}}", description: var[:description] }
    end
  end

  def available_models = models_for_provider
  def available_image_models = models_for_provider(filter: :image)
  def available_tools = Tool.enabled.where(operation: mission.operation).ordered

  def selected_tool_ids
    Array(node_data["tool_ids"]).filter_map { |value| Integer(value, exception: false) }
  end

  private

  def find_node
    nodes.find { |entry| entry["id"] == node_id }
  end

  def node_klass
    @node_klass ||= MissionNodePlugin.resolve(node_type)
  end

  def models_for_provider(filter: nil)
    connector_id = node_data["connector_id"]
    return [] if connector_id.blank?

    connector = ConnectorLookup.find(connector_id, tenant: mission.operation.tenant)
    provider = connector&.connector_type == "llm_provider" ? connector.provider : nil
    return [] if provider.blank?

    scope = Model.where(provider:).order(:name).picker_projection
    scope = scope.where("modalities -> 'output' @> '\"image\"'") if filter == :image
    scope
  end

  def resolve_metadata
    return {} unless node_type

    MissionNodePlugin.metadata_for(node_type) || {}
  end

  def variable_schema
    return Missions::VariableSchema.new unless node_klass

    node_klass.variable_schema
  end

  def compute_validation_errors
    return [] unless node_type

    errors = Missions::NodeConfigValidator.validate_flow(flow_data)
    errors[node_id] || []
  end

  def http_hash_config(key)
    value = data_raw(key)
    case value
    when Hash
      value
    when String
      JSON.parse(value)
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def flow_data
    @flow_data ||= begin
      raw_flow = mission.flow_data || {}
      raw_flow.merge(
        "nodes" => Array(raw_flow["nodes"]),
        "edges" => Array(raw_flow["edges"]),
      )
    end
  end

  def nodes
    @nodes ||= flow_data["nodes"]
  end

  def node_map
    @node_map ||= nodes.index_by { |entry| entry["id"] }
  end

  def boolean_http_setting(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def sanitize_icon_class(value)
    icon = value.to_s.strip
    return "fa-solid fa-circle" unless icon.match?(ICON_CLASS_PATTERN)

    filtered = icon.split.filter { |token| token.start_with?("fa-") }
    filtered.any? ? filtered.join(" ") : "fa-solid fa-circle"
  end

  def sanitize_hex_color(value)
    color = value.to_s.strip
    HEX_COLOR_PATTERN.match?(color) ? color : "#6366f1"
  end
end
