# frozen_string_literal: true

# Provides the tool plugin protocol for tool configurator models.
#
# Each tool class (for example Tools::SqlQuery, Tools::McpServer, etc.)
# includes this concern and implements:
#
# Class methods (metadata & params):
#   - type_key          → "sql_query"
#   - type_label        → "SQL Query"
#   - type_icon         → "fa-solid fa-database"
#   - tool_widget_default_presentation(display_name:, icon:) → ToolCalls::Presentation
#   - tool_designer_action_definitions → available designer-managed actions
#   - tool_designer_state_attributes   → state entries read_tool may display
#   - permitted_params  → strong params extraction
#   - build_from_params → factory for new instances
#
# Instance methods (behavior):
#   - perform_discovery!
#   - update_visibility!
#   - visibility_available?
#   - form_partial_path
#   - show_partial_path
#   - edit_visibility_partial_path
module ToolPlugin
  extend ActiveSupport::Concern
  extend ToolPluginRegistry

  Result = Data.define(:success?, :message)
  TOOL_DESIGNER_ACTIONS = {
    "discover" => {
      method_name: :perform_discovery!,
      description: "Run the built-in discovery step for this tool type.",
      policy_query: :discover_schema?,
      arguments: [],
    },
    "set_visibility" => {
      method_name: :update_visibility!,
      description: "Update which discovered items stay visible to the runtime tool.",
      policy_query: :update_visibility?,
      arguments: [
        {
          "name" => "selected_items",
          "type" => "array",
          "required" => false,
          "description" => "The complete desired list of discovered item names to expose.",
        },
      ],
    },
  }.freeze

  @type_map = {}
  @label_map = {}
  @icon_map = {}
  @description_map = {}

  module ClassMethods
    def type_key
      name.demodulize.underscore
    end

    def type_label
      name.demodulize.titleize
    end

    def type_icon
      "fa-solid fa-wrench"
    end

    def tool_widget_default_presentation(display_name:, icon:)
      ToolCalls::Presentation.new(display_name:, icon:)
    end

    def permitted_params(_params = nil)
      []
    end

    def build_from_params(params)
      new(permitted_params(params))
    end

    def tool_designer_editable_attributes
      return [] unless respond_to?(:attribute_names)

      attribute_names.map(&:to_s)
    end

    def tool_designer_notes
      []
    end

    def tool_designer_field_hints
      {}
    end

    def tool_designer_resource_kinds
      []
    end

    def resource_hint(resource_kind, note: nil)
      {
        "resource_kind" => resource_kind,
        "note" => note,
      }.compact
    end

    def tool_designer_resource_kind(kind:, title:, model_name:, scope:)
      {
        "kind" => kind,
        "title" => title,
        "model_name" => model_name,
        "scope" => scope,
      }
    end

    def tool_designer_state_attributes
      []
    end

    def tool_designer_state_attribute(label:, method:, empty: false)
      {
        "label" => label,
        "method" => method.to_s,
        "empty" => empty,
      }
    end

    def tool_designer_action_definitions
      ToolPlugin::TOOL_DESIGNER_ACTIONS.filter_map do |key, metadata|
        next unless tool_designer_supports?(metadata.fetch(:method_name))

        tool_designer_action(
          key:,
          description: metadata.fetch(:description),
          policy_query: metadata.fetch(:policy_query),
          arguments: metadata.fetch(:arguments),
        )
      end
    end

    def tool_designer_action(key:, description:, arguments: [], policy_query: nil)
      {
        "key" => key.to_s,
        "description" => description,
        "arguments" => Array(arguments),
        "policy_query" => policy_query&.to_s,
      }.compact
    end

    def tool_designer_actions
      tool_designer_action_definitions.map do |definition|
        definition.slice("key", "description", "arguments")
      end
    end

    def tool_designer_action_definition(action_key)
      tool_designer_action_definitions.find { |definition| definition.fetch("key") == action_key.to_s }
    end

    def tool_designer_action_policy_query(action_key)
      definition = tool_designer_action_definition(action_key)
      return unless definition

      definition.fetch("policy_query", nil).presence&.to_sym
    end

    def runtime_tool_adapter_class_name
      nil
    end

    def runtime_tool_adapter_keywords
      []
    end

    def build_runtime_tool(tool_record, agent: nil, parent_chat: nil)
      adapter_class_name = runtime_tool_adapter_class_name
      return if adapter_class_name.blank?

      adapter_class = adapter_class_name.constantize
      keywords = {}

      keywords[:agent] = agent if runtime_tool_adapter_keywords.include?(:agent)
      keywords[:parent_chat] = parent_chat if runtime_tool_adapter_keywords.include?(:parent_chat)

      return adapter_class.for_tool(tool_record) if keywords.empty?

      adapter_class.for_tool(tool_record, **keywords)
    end

    def tool_runtime_name_prefix
      type_key
    end

    def tool_runtime_name(tool_record:, toolable: nil)
      _ = toolable

      prefix = tool_runtime_name_prefix
      fragment = ToolPlugin.sanitize_runtime_fragment(tool_record&.name)
      return if prefix.blank? || fragment.blank?

      "#{prefix}_#{fragment}"
    end

    def tool_runtime_names(tool_record:, toolable: nil)
      runtime_name = tool_runtime_name(tool_record:, toolable:)
      runtime_name.present? ? [runtime_name] : []
    end

    def tool_runtime_display_name(runtime_name:, tool_record:, toolable: nil)
      _ = runtime_name
      _ = toolable

      tool_record&.name
    end

    def register_builtin_tools(_registrations)
      nil
    end

    private

    def tool_designer_supports?(method_name)
      instance_method(method_name).owner != ToolPlugin
    end
  end

  def perform_discovery!
    Result.new(success?: false, message: "Discovery not supported for this tool type")
  end

  def update_visibility!(_raw_params)
    raise NotImplementedError, "#{self.class} does not support visibility editing"
  end

  def visibility_available?
    false
  end

  def form_partial_path
    "tools/#{self.class.type_key.pluralize}/form"
  end

  def show_partial_path
    "tools/#{self.class.type_key.pluralize}/show"
  end

  def edit_visibility_partial_path
    "tools/#{self.class.type_key.pluralize}/edit_visibility"
  end

  def visibility_param_key
    nil
  end

  def tool_designer_state
    self.class.tool_designer_state_attributes.filter_map do |entry|
      state_entry = entry.to_h.stringify_keys
      method_name = state_entry["method"]
      next if method_name.blank? || !respond_to?(method_name)

      value = public_send(method_name)
      next if value.blank? && !state_entry["empty"]

      {
        "label" => state_entry["label"].presence || method_name.humanize,
        "value" => value,
      }
    end
  end

  def perform_tool_designer_action!(action_key, arguments = {})
    action_definition = self.class.tool_designer_action_definition(action_key)
    unless action_definition
      raise ArgumentError, "Action '#{action_key}' is not supported for #{self.class.type_label}."
    end

    case action_definition.fetch("key")
    when "discover"
      perform_discovery!
    when "set_visibility"
      perform_tool_designer_visibility_action!(arguments)
    else
      raise NotImplementedError, "Action '#{action_key}' is declared but not implemented by #{self.class.type_label}."
    end
  end

  def tool_tenant
    tool&.operation&.tenant
  end

  def find_connector(connector_id)
    ConnectorLookup.find(connector_id, tenant: tool_tenant)
  end

  def tool
    return _tool_record if respond_to?(:_tool_record) && _tool_record.present?

    # :nocov:
    return nil unless respond_to?(:id) && id.present?

    Tool.where(tool_type: self.class.type_key)
        .where("configuration ->> 'record_id' = ?", id.to_s)
        .first
    # :nocov:
  end

  def perform_tool_designer_visibility_action!(arguments)
    param_key = visibility_param_key
    raise ArgumentError, "Visibility updates are not supported for #{self.class.type_label}." if param_key.blank?

    normalized_arguments = arguments.to_h.stringify_keys
    update_visibility!(
      ActionController::Parameters.new(
        self.class.type_key => { param_key => Array(normalized_arguments["selected_items"]) },
      ),
    )
    tool_designer_action_result(nil, "tools.visibility_updated")
  end

  def tool_designer_action_result(error, success_key)
    Result.new(success?: error.blank?, message: error || I18n.t(success_key))
  end

  # ── Persistence (delegates to _tool_record) ─────────────────────
  #
  # These methods assume the including class exposes a `_tool_record`
  # accessor (set by Tool#build_configurator) and implements
  # `to_configuration` + `self.class.attribute_names`.

  def id
    _tool_record&.id
  end

  def save!
    raise "No _tool_record set" unless _tool_record

    _tool_record.update!(configuration: to_configuration)
    self
  end

  def update!(attrs = {})
    attrs.each { |k, v| public_send(:"#{k}=", v) }
    save!
  end

  def reload
    return self unless _tool_record

    _tool_record.reload
    fresh = self.class.new((_tool_record.configuration || {}).symbolize_keys)
    self.class.attribute_names.each { |name| public_send(:"#{name}=", fresh.public_send(name)) }
    reset_configurator_caches
    self
  end

  def ==(other)
    return super unless other.is_a?(self.class)
    return id == other.id if id && other.id

    super
  end

  # Override in including configurators to clear cached associations after reload.
  def reset_configurator_caches
    # no-op by default
  end
end
