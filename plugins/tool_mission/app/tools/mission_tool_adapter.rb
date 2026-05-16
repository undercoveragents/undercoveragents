# frozen_string_literal: true

# RubyLLM tool that executes a mission as an agent tool.
#
# Dynamically builds parameters from the mission's input fields and
# executes the mission via Missions::Runner, returning the output.
#
# Each enabled Mission tool produces its own MissionToolAdapter instance
# so that multiple missions can be offered to the LLM simultaneously.
#
# Usage:
#   tool_record = Tool.mission_tools.enabled.find(id)
#   tool = MissionToolAdapter.for_tool(tool_record)
#   chat.with_tool(tool)
#   chat.ask("Run the workflow with username jdoe")
#
class MissionToolAdapter < RubyLLM::Tool
  FIELD_TYPE_MAP = {
    "string" => :string,
    "string_array" => :string,
    "number" => :number,
    "number_array" => :string,
    "boolean" => :boolean,
    "boolean_array" => :string,
    "file" => :string,
    "file_array" => :string,
    "json" => :string,
    "date" => :string,
    "date_array" => :string,
    "datetime" => :string,
    "datetime_array" => :string,
  }.freeze

  def self.for_tool(tool_record)
    raise ArgumentError, "Expected a Mission tool" unless tool_record.toolable.is_a?(Tools::MissionTool)

    new(tool_record)
  end

  def initialize(tool_record)
    super()
    @tool_record = tool_record
    @mission_tool = tool_record.toolable
  end

  def name
    sanitize_tool_name
  end

  def description
    desc = @tool_record.description.presence || @mission_tool.mission&.description
    desc.presence || "Execute the #{@mission_tool.mission&.name || "mission"} workflow"
  end

  def parameters
    build_parameters
  end

  def execute(**params)
    mission = @mission_tool.mission
    return "Mission not found" unless mission

    trigger_data = build_trigger_data(params)
    run = Missions::Runner.new(mission).execute(variables: trigger_data, trigger_data:)

    format_output(run)
  rescue StandardError => e
    Rails.logger.error "[MissionToolAdapter] Execution failed for '#{@tool_record.name}': #{e.message}"
    "Mission execution failed: #{e.message}"
  end

  private

  def sanitize_tool_name
    base = @tool_record.name
                       .unicode_normalize(:nfkd)
                       .encode("ASCII", replace: "")
                       .gsub(/[^a-zA-Z0-9_-]/, "_").squeeze("_")
                       .gsub(/\A_|_\z/, "")
                       .downcase

    "mission_#{base}"
  end

  def build_parameters
    fields = @mission_tool.input_fields
    return default_parameters if fields.empty?

    fields.each_with_object({}) do |field, params|
      var_name = field["variable_name"]
      next if var_name.blank?

      field_type = field["field_type"] || "string"
      ruby_type = FIELD_TYPE_MAP.fetch(field_type, :string)
      required = field["required"].present?
      field_desc = field["label"].presence || var_name.humanize

      params[var_name.to_sym] = RubyLLM::Parameter.new(var_name.to_sym, type: ruby_type, desc: field_desc, required:)
    end
  end

  def default_parameters
    { input: RubyLLM::Parameter.new(:input, type: :string, desc: "Input to pass to the mission", required: false) }
  end

  def build_trigger_data(params)
    params.transform_keys(&:to_s)
  end

  def format_output(run)
    return "Mission failed: #{run.error || "Unknown error"}" unless run.completed?

    format_completed_output(run.variables || {})
  end

  def format_completed_output(variables)
    output_meta = variables["_output_meta"]
    if output_meta.is_a?(Hash) && output_meta["response_body"].present?
      return format_response_body(output_meta["response_body"], variables)
    end

    format_selected_output(variables)
  end

  def format_selected_output(variables)
    selected = @mission_tool.output_variables
    if selected.any?
      values = selected.index_with { |key| variables[key] }
      return format_mixed_output(values) if values.any? { |_, v| contains_file?(v) }

      return values.to_json
    end

    fallback = variables["output"] || "Mission completed successfully"
    return format_file_as_markdown(fallback) if file_variable?(fallback)

    fallback.to_s
  end

  # ── File variable helpers ─────────────────────────────────────

  def file_variable?(value)
    value.is_a?(Hash) && value["blob_id"].present? && value["filename"].present?
  end

  def format_response_body(body, variables)
    parsed = parse_file_json(body)
    return format_file_as_markdown(parsed) if parsed

    # Check if output variable is a file and response_body is just its stringified form
    file_var = find_file_in_variables(variables)
    return format_file_as_markdown(file_var) if file_var

    body
  end

  def parse_file_json(body)
    parsed = JSON.parse(body)
    file_variable?(parsed) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def find_file_in_variables(variables)
    variables.each_value { |v| return v if file_variable?(v) }
    nil
  end

  def contains_file?(value)
    return true if file_variable?(value)
    return value.any? { |v| file_variable?(v) } if value.is_a?(Array)

    false
  end

  def format_mixed_output(values)
    values.map { |key, val| format_output_entry(key, val) }.join("\n\n")
  end

  def format_output_entry(key, value)
    return format_file_entry(value) if file_variable?(value)
    return format_file_array_entry(value) if value.is_a?(Array) && value.any? { |v| file_variable?(v) }

    "#{key}: #{value.is_a?(String) ? value : value.to_json}"
  end

  def format_file_entry(file_hash)
    markdown_link(file_hash) || "File: #{file_hash["filename"]}"
  end

  def format_file_array_entry(files)
    files.filter_map { |f| format_file_entry(f) if file_variable?(f) }.join("\n")
  end

  def format_file_as_markdown(file_hash)
    link = markdown_link(file_hash)
    link ? "File generated: #{link}" : "File generated: #{file_hash["filename"]}"
  end

  def markdown_link(file_hash)
    url = resolve_file_url(file_hash)
    url ? "[📎 #{file_hash["filename"]}](#{url})" : nil
  end

  def resolve_file_url(file_hash)
    blob = ActiveStorage::Blob.find_by(id: file_hash["blob_id"])
    return nil unless blob

    signed_id = blob.signed_id
    url_options = Rails.application.routes.default_url_options
                       .presence || Rails.application.config.action_mailer.default_url_options || {}
    Rails.application.routes.url_helpers.short_download_url(signed_id, file_hash["filename"], **url_options)
  end
end
