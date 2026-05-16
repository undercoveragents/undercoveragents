# frozen_string_literal: true

module ListResourcesToolPluginResources
  private

  def connector_resource_definitions
    @connector_resource_definitions ||= ConnectorPlugin.all_types.each_with_object({}) do |type, definitions|
      connector_class = ConnectorPlugin.resolve(type.fetch(:key))
    rescue NameError
      next
    else
      next unless connector_class.respond_to?(:list_resources_kind)

      kind = connector_class.list_resources_kind.to_s
      next if kind.blank?

      definitions[kind] = {
        connector_type: type.fetch(:key),
        title: connector_resource_title(connector_class, type),
      }
    end
  end

  def connector_resource_title(connector_class, type)
    return connector_class.list_resources_title if connector_class.respond_to?(:list_resources_title)

    type.fetch(:label).to_s.pluralize
  end

  def registered_resource_definitions
    @registered_resource_definitions ||= ToolPlugin.all_types.each_with_object({}) do |type, definitions|
      tool_class = ToolPlugin.resolve(type.fetch(:key))
    rescue NameError
      next
    else
      next unless tool_class

      append_tool_resource_definitions(definitions, tool_class.tool_designer_resource_kinds)
    end
  end

  def append_tool_resource_definitions(definitions, resource_kinds)
    Array(resource_kinds).each do |definition|
      normalized_definition = normalize_resource_definition(definition)
      next unless normalized_definition

      definitions[normalized_definition.fetch("kind")] = normalized_definition
    end
  end

  def normalize_resource_definition(definition)
    return unless definition.respond_to?(:to_h)

    normalized_definition = definition.to_h.stringify_keys
    return if normalized_definition["kind"].blank? || normalized_definition["model_name"].blank?

    normalized_definition["title"] ||= normalized_definition.fetch("kind").tr("_", " ").titleize
    normalized_definition["scope"] ||= "operation_owned"
    normalized_definition
  end

  def render_connector_kind(kind)
    definition = connector_resource_definitions.fetch(kind)
    render_connector_collection(
      title: definition.fetch(:title),
      scope: tenant.connectors.where(connector_type: definition.fetch(:connector_type)).enabled.ordered,
    )
  end

  def render_registered_resource_kind(kind)
    definition = registered_resource_definitions.fetch(kind)
    render_named_records(
      title: definition.fetch("title"),
      scope: scoped_registered_records(definition),
    )
  end

  def scoped_registered_records(definition)
    model_class = definition.fetch("model_name").constantize
    scope = model_class.order(:name)

    case definition.fetch("scope")
    when "operation_owned"
      scope_registered_records_by_operation(scope)
    when "tenant_owned"
      scope.where(tenant:)
    else
      scope.none
    end
  end

  def scope_registered_records_by_operation(scope)
    return scope.where(operation: scoped_operation) if scoped_operation

    return scope.none unless tenant
    return scope.none unless scope.klass.reflect_on_association(:operation)

    scope.joins(:operation).where(operations: { tenant_id: tenant.id })
  end

  def render_connector_collection(title:, scope:)
    return "No #{empty_collection_label(title)} available." if scope.empty?

    lines = ["## #{title}"]
    scope.each { |connector| lines << "- `#{connector.id}` — #{connector.name}" }
    lines.join("\n")
  end

  def render_named_records(title:, scope:)
    return "No #{empty_collection_label(title)} available." if scope.empty?

    lines = ["## #{title}"]
    scope.each { |record| lines << "- `#{record.id}` — #{record.name}" }
    lines.join("\n")
  end

  def empty_collection_label(title)
    title.split.map { |word| word == word.upcase ? word : word.downcase }.join(" ")
  end
end
