# frozen_string_literal: true

class ManageRecordTool < RubyLLM::Tool
  include ManageRecordAgentTypeDefaulting
  include RuntimeRecordFeedback

  ATTRIBUTES_DESCRIPTION = [
    "Hash or JSON object string of record attributes for create or update.",
    "Missions support name and description.",
    "Agents support name, description, instructions, agent_type, enabled, selectable, llm_config_source,",
    "llm_connector_id, model_id, temperature, thinking_effort, thinking_budget, response_format,",
    "response_schema, custom_llm_params,",
    "model_routing_config,",
    "input_schema, assigned_tool_ids, subagent_ids, and skill_catalog_ids.",
    "Skill catalogs support name and description.",
    "Test suites support name, description, suite_type, agent_id, mission_id, evaluation_llm_connector_id,",
    "evaluation_model_id, and evaluation_temperature.",
    "Channels support name, channel_type, description, enabled, default, connector_id, agent_id, mission_id,",
    "agent_ids, mission_ids, access_scope, response_mode, callback_url, title, welcome_message, footer, and",
    "the configuration-backed label fields.",
    "Tools support tool_type, name, description, enabled, and nested toolable_attributes for the type-specific",
    "configuration.",
  ].join(" ")
  DESCRIPTION = [
    "Create, update, delete, or clone a supported admin record inside the current tenant and operation.",
    "Clone is supported for missions, agents, and tools.",
    "Currently supports missions, agents, skill catalogs, test suites, channels, and tools.",
  ].join(" ")
  NAVIGATE_DESCRIPTION = [
    "Whether to navigate the admin UI after success.",
    "Defaults to true for create/clone/delete and false for update unless page is provided.",
  ].join(" ")
  PAGE_DESCRIPTION = [
    "Optional page to visit after success.",
    "Missions support index, edit, and designer.",
    "Agents support index, show, edit, and prompt_preview.",
    "Skill catalogs support index, show, and edit.",
    "Test suites support index, show, and edit.",
    "Channels support index, show, edit, and preview (preview is client-channel only).",
    "Tools support index, new, show, and edit.",
  ].join(" ")

  description DESCRIPTION

  param :resource,
        desc: [
          "The resource type.",
          "Supported values: 'mission', 'agent', 'skill_catalog', 'test_suite', 'channel', or 'tool'.",
        ].join(" ")

  param :action,
        desc: "The mutation to perform: 'create', 'update', 'delete', or 'clone'."

  param :record_id,
        desc: "Required for clone, update, and delete. Accepts a numeric ID or a slug.",
        required: false

  param :attributes, desc: ATTRIBUTES_DESCRIPTION, required: false

  param :page, desc: PAGE_DESCRIPTION, required: false

  param :navigate, desc: NAVIGATE_DESCRIPTION, required: false

  param :confirm_destroy,
        desc: "Must be true for delete actions. Only use delete when the user explicitly asked for it.",
        required: false

  def initialize(agent: nil, parent_chat: nil, mission: nil, ui_context: nil)
    super()
    @runtime_context = BuiltinTools::RuntimeContext.build(agent:, parent_chat:, mission:, ui_context:)
  end

  def name = "manage_record"

  def description = DESCRIPTION

  def execute(**options)
    manager = RuntimeRecords::Manager.new(@runtime_context)
    action = options[:action].to_s

    case action
    when "create"
      create_record(manager, options)
    when "clone"
      clone_record(manager, options)
    when "update"
      update_record(manager, options)
    when "delete"
      delete_record(manager, options)
    else
      "Error: Unknown action '#{action}'. Use create, clone, update, or delete."
    end
  rescue ActiveRecord::RecordInvalid => e
    "Error: #{e.record.errors.full_messages.to_sentence}"
  rescue ActiveRecord::RecordNotFound, ArgumentError, JSON::ParserError, KeyError, Pundit::NotAuthorizedError => e
    "Error: #{e.message}"
  rescue StandardError => e
    "Failed to manage #{options[:resource]}: #{e.message}"
  end

  private

  def create_record(manager, options)
    attributes = normalize_create_attributes(options[:resource], options[:attributes])
    return "Error: Provide attributes for create." if attributes.blank?

    result = manager.create(resource: options[:resource], attributes:)
    path = create_path(manager, options, result)
    navigated = perform_navigation?(path, requested_navigation?(options, default: true))
    refreshed = perform_refresh?(resource: options[:resource], result:, navigated:)

    success_message(result:, path:, navigated:, refreshed:)
  end

  def update_record(manager, options)
    record_id = options[:record_id]
    attributes = options[:attributes]
    return "Error: Provide record_id for update." if record_id.blank?
    return "Error: Provide attributes for update." if attributes.blank?

    result = manager.update(resource: options[:resource], record_id:, attributes:)
    path = update_path(manager, options, result)
    navigated = perform_navigation?(path, requested_navigation?(options, default: false))
    refreshed = perform_refresh?(resource: options[:resource], result:, navigated:)

    success_message(result:, path:, navigated:, refreshed:)
  end

  def clone_record(manager, options)
    record_id = options[:record_id]
    return "Error: Provide record_id for clone." if record_id.blank?

    result = manager.clone(resource: options[:resource], record_id:)
    path = clone_path(manager, options, result)
    navigated = perform_navigation?(path, requested_navigation?(options, default: true))
    refreshed = perform_refresh?(resource: options[:resource], result:, navigated:)

    success_message(result:, path:, navigated:, refreshed:)
  end

  def delete_record(manager, options)
    record_id = options[:record_id]
    return "Error: Provide record_id for delete." if record_id.blank?
    return "Error: confirm_destroy must be true for delete actions." unless boolean(options[:confirm_destroy])

    result = manager.destroy(resource: options[:resource], record_id:)
    path = delete_path(manager, options, result)
    navigated = perform_navigation?(path, requested_navigation?(options, default: true))
    refreshed = perform_refresh?(resource: options[:resource], result:, navigated:)

    success_message(result:, path:, navigated:, refreshed:)
  end

  def boolean(value) = ActiveModel::Type::Boolean.new.cast(value)

  def requested_navigation?(options, default:)
    navigate = options[:navigate]
    page = options[:page]

    return true if page.present? && navigate.nil?
    return boolean(navigate) unless navigate.nil?

    default
  end

  def perform_navigation?(path, requested)
    return false unless requested
    return false if path.blank?

    RuntimeRecords::Navigation.broadcast!(chat: @runtime_context.chat, path:) == :broadcasted
  end

  def perform_refresh?(resource:, result:, navigated:)
    return false if navigated
    return false if result.record.blank?

    RuntimeRecords::Refresh.broadcast!(
      context: @runtime_context,
      resource:,
      record: result.record,
      action: result.action,
    ) == :broadcasted
  end

  def create_path(manager, options, result)
    return result.path if options[:page].blank?

    manager.navigation_path(resource: options[:resource], page: options[:page], record_id: result.record.id)
  end

  def clone_path(manager, options, result)
    return result.path if options[:page].blank?

    manager.navigation_path(resource: options[:resource], page: options[:page], record_id: result.record.id)
  end

  def update_path(manager, options, result)
    return unless requested_navigation?(options, default: false) || options[:page].present?

    manager.navigation_path(
      resource: options[:resource],
      page: options[:page].presence ||
        result.definition.default_page_for(record: result.record, context: @runtime_context),
      record_id: result.record.id,
    )
  end

  def delete_path(manager, options, result)
    return result.path if options[:page].blank?

    manager.navigation_path(resource: options[:resource], page: options[:page])
  end
end
