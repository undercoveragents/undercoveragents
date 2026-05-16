# frozen_string_literal: true

module Tools
  module SqlQueryToolProtocol
    def type_key = "sql_query"
    def type_label = "SQL Query"
    def type_icon = "fa-solid fa-database"

    def tool_widget_default_presentation(display_name:, icon:)
      ToolCalls::Presentation.new(
        display_name:,
        icon:,
        running_messages: [
          "Drafting a safe SQL query…",
          "Checking the visible tables…",
          "Translating the question into SQL…",
        ],
        complete_messages: [
          "Database results are ready.",
          "SQL response collected.",
          "Query execution completed.",
        ],
      )
    end

    def tool_designer_editable_attributes
      [
        "connector_id",
        "instructions",
        "llm_config_source",
        "llm_connector_id",
        "model_id",
        "temperature",
        *ToolWidgetConfigurable::DESIGNER_ATTRIBUTE_KEYS,
      ]
    end

    def tool_designer_notes
      [
        "Use list_resources(kind: \"sql_database_connectors\") to resolve connector_id values.",
        "When llm_config_source is custom, also set llm_connector_id, model_id, and temperature.",
        "selected_objects is managed through the set_visibility action after discovery instead of direct updates.",
        "Discovery and visibility updates regenerate the tool instructions from the visible schema automatically.",
      ]
    end

    def tool_designer_field_hints
      {
        "connector_id" => resource_hint("sql_database_connectors"),
        "llm_connector_id" => resource_hint("llm_connectors"),
        "model_id" => resource_hint("models", note: "Pass connector_id: llm_connector_id."),
      }
    end

    def tool_designer_state_attributes
      [
        tool_designer_state_attribute(label: "Schema discovered at", method: :schema_discovered_at),
        tool_designer_state_attribute(label: "Visible objects", method: :selected_object_names, empty: true),
        tool_designer_state_attribute(label: "Discovered objects", method: :all_discovered_object_names),
      ]
    end

    def runtime_tool_adapter_class_name = "SqlQueryTool"

    def runtime_tool_adapter_keywords = [:agent, :parent_chat]

    def register_builtin_tools(registrations)
      register_schema_explorer_builtin(registrations)
    end

    def permitted_params(params)
      permit_params_with_widget(
        params,
        [:connector_id, :instructions,
         :llm_config_source, :llm_connector_id, :model_id, :temperature,],
      )
        .merge(schema_analysis_llm_connector_id: nil, schema_analysis_model_id: nil)
    end

    def build_from_params(params)
      new(permitted_params(params))
    end

    def register_schema_explorer_builtin(registrations)
      register_sql_builtin(
        registrations,
        "sql.schema_explorer",
        name: "Schema Explorer",
        description: "Run read-only exploration queries against a SQL database schema.",
        runtime_name: "explore_database",
        icon: "fa-solid fa-database",
        compaction_policy: :replace_by_args,
        running_messages: [
          "Exploring the database schema…",
          "Running read-only discovery queries…",
          "Collecting table and column context…",
        ],
        complete_messages: [
          "Schema context collected.",
          "Database exploration completed.",
          "Read-only results are ready.",
        ],
      ) { |sql_database:, **| SchemaExplorerTool.for_sql_database(sql_database) }
    end

    def register_sql_builtin(registrations, key, **attributes, &)
      running_messages = attributes.delete(:running_messages)
      complete_messages = attributes.delete(:complete_messages)

      BuiltinTools::Registry.register(
        key,
        visible_in_headquarter: true,
        tool_call_presentation: registrations.tool_call_presentation(running_messages:, complete_messages:),
        **attributes,
        &
      )
    end
  end
end
