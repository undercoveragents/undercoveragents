# frozen_string_literal: true

module MissionsHelper
  CATEGORY_META = {
    "global" => { label: "Global Variables", icon: "fa-solid fa-globe", color: "#10b981" },
    "trigger" => { label: "Trigger Inputs", icon: "fa-solid fa-bolt", color: "#f59e0b" },
    "template" => { label: "Template Variables", icon: "fa-solid fa-code", color: "#6366f1" },
    "expression" => { label: "Expression Variables", icon: "fa-solid fa-calculator", color: "#8b5cf6" },
    "custom" => { label: "Custom Variables", icon: "fa-solid fa-plus-circle", color: "#06b6d4" },
  }.freeze

  STATUS_CONFIG = {
    "success" => { icon: "fa-circle-check", color: "#16a34a", label: "Success" },
    "failure" => { icon: "fa-circle-xmark", color: "#dc2626", label: "Failed" },
    "running" => { icon: "fa-spinner fa-spin", color: "#6366f1", label: "Running" },
    "pending" => { icon: "fa-clock", color: "#d97706", label: "Pending" },
    "skip" => { icon: "fa-forward", color: "#9ca3af", label: "Skipped" },
    "cancelled" => { icon: "fa-ban", color: "#9ca3af", label: "Cancelled" },
  }.freeze

  RUN_STATUS_CONFIG = {
    "running" => { icon: "fa-spinner fa-spin", color: "#6366f1", bg: "rgba(99,102,241,0.1)" },
    "completed" => { icon: "fa-circle-check", color: "#16a34a", bg: "rgba(22,163,106,0.1)" },
    "failed" => { icon: "fa-circle-xmark", color: "#dc2626", bg: "rgba(220,38,38,0.1)" },
    "cancelled" => { icon: "fa-ban", color: "#d97706", bg: "rgba(217,119,6,0.1)" },
    "pending" => { icon: "fa-clock", color: "#9ca3af", bg: "rgba(156,163,175,0.1)" },
    "none" => { icon: "fa-circle", color: "#9ca3af", bg: "rgba(156,163,175,0.1)" },
  }.freeze

  # Extract input variables from mission flow_data nodes.
  # Delegates to each node class's extract_variables method, which may be backed
  # by field_contract metadata rather than bespoke extraction code.
  def extract_workflow_variables(flow_data)
    nodes = flow_data&.dig("nodes") || []
    variables = []
    seen = Set.new

    extract_global_variables(flow_data, variables, seen)

    nodes.each do |node|
      extract_node_variables(node, variables, seen)
    end

    variables
  end

  def format_debug_output(value)
    case value
    when String then value
    when NilClass then ""
    else JSON.pretty_generate(value)
    end
  rescue JSON::GeneratorError
    value.to_s
  end

  def image_output?(output)
    output.is_a?(String) && output.match?(%r{\Adata:image/[^;]+;base64,})
  end

  def file_output?(value)
    single_file?(value) || (value.is_a?(Array) && value.any? { |v| single_file?(v) })
  end

  def file_download_link(value)
    return file_download_links(value) if value.is_a?(Array)

    render_single_file_link(value)
  end

  def status_badge_html(status)
    config = STATUS_CONFIG[status.to_s] || { icon: "fa-circle", color: "#9ca3af", label: status }
    tag.span(class: "ms-debug-status", style: "color: #{config[:color]}") do
      tag.i(class: "fa-solid #{config[:icon]}") + " #{config[:label]}"
    end
  end

  def debug_timeline_entry_payload(entry)
    status = debug_entry_value(entry, :status)
    node_type = debug_entry_value(entry, :node_type)
    input = debug_entry_value(entry, :input)
    output = debug_entry_value(entry, :output)

    {
      status:,
      node_id: debug_entry_value(entry, :node_id),
      node_type:,
      input:,
      output:,
      next_port: debug_entry_value(entry, :next_port),
      error: debug_entry_value(entry, :error),
      duration_ms: debug_entry_value(entry, :duration_ms),
      node_label: debug_entry_value(entry, :node_label),
      input_present: debug_value_present?(input),
      output_present: debug_value_present?(output),
      meta: node_type_meta(node_type),
      status_cfg: STATUS_CONFIG[status.to_s] || { icon: "fa-circle", color: "#9ca3af", label: status },
    }
  end

  def node_type_meta(node_type)
    MissionNodePlugin.metadata_for(node_type) || { label: node_type.to_s.humanize, icon: "fa-solid fa-cube",
                                                   color: "#9ca3af", }
  end

  def run_status_config(status)
    RUN_STATUS_CONFIG[status.to_s] || RUN_STATUS_CONFIG["none"]
  end

  # Returns a JSON-safe hash of node config inputs and outputs for all node
  # types, keyed by node_type string. Inputs come from field_contracts and
  # outputs come from variable_schema.
  def node_variable_schemas_json
    MissionNodePlugin.type_keys.each_with_object({}) do |key, map|
      klass = MissionNodePlugin.resolve(key)
      next unless klass

      map[key] = {
        inputs: klass.input_schema,
        outputs: klass.variable_schema.to_h[:outputs],
      }
    end.to_json
  end

  private

  def debug_entry_value(entry, key)
    entry[key] || entry[key.to_s]
  end

  def debug_value_present?(value)
    !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
  end

  def single_file?(value)
    value.is_a?(Hash) && value["blob_id"].present? && value["filename"].present?
  end

  def extract_global_variables(flow_data, variables, seen)
    (flow_data&.dig("global_variables") || []).each do |var|
      key = var["key"]
      next if key.blank? || seen.include?(key)

      seen.add(key)
      entry = { key:, category: "global", source: "Global", description: "Global variable (#{var["type"]})" }
      entry[:default_value] = var["value"] if var["value"].present?
      variables << entry
    end
  end

  def extract_node_variables(node, variables, seen)
    data = node["data"] || {}
    label = data["label"] || node["type"]
    node_type = node["type"]
    klass = MissionNodePlugin.resolve(node_type)
    before_count = variables.size
    klass&.extract_variables(data, label, variables, seen)
    variables[before_count..].each { |v| v[:node_type] = node_type }
  end

  def render_single_file_link(value)
    blob = ActiveStorage::Blob.find_by(id: value["blob_id"])
    return value["filename"] unless blob

    path = Rails.application.routes.url_helpers.rails_blob_path(blob, disposition: "attachment", only_path: true)
    link = tag.a(href: path, class: "ms-debug-file-link", target: "_blank", rel: "noopener") do
      tag.i(class: "fa-solid fa-download") + " #{blob.filename}"
    end

    return link unless blob.content_type&.start_with?("image/")

    preview_path = Rails.application.routes.url_helpers.rails_blob_path(blob, disposition: "inline", only_path: true)
    preview = tag.img(src: preview_path, alt: blob.filename, class: "ms-debug-image-preview")
    link + preview
  end

  def file_download_links(values)
    safe_join(values.filter_map { |v| render_single_file_link(v) if single_file?(v) }, tag.br)
  end
end
