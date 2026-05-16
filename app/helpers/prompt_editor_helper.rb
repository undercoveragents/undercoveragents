# frozen_string_literal: true

module PromptEditorHelper
  PromptEditorConfig = Data.define(
    :compact,
    :show_variables,
    :show_user_messages,
    :user_messages,
    :variables,
    :field_name,
    :system_value,
    :var_names,
    :variables_json,
    :var_labels,
  )

  def build_prompt_editor_config(local_assigns)
    variables = Array(local_assigns.fetch(:variables, []))
    var_names = variables.filter_map do |variable|
      next variable if variable.is_a?(String)

      variable[:name] || variable["name"]
    end

    PromptEditorConfig.new(
      compact: local_assigns.fetch(:compact, false),
      show_variables: local_assigns.fetch(:show_variables, false),
      show_user_messages: local_assigns.fetch(:show_user_messages, true),
      user_messages: Array(local_assigns.fetch(:user_messages, [])),
      variables:,
      field_name: local_assigns.fetch(:field_name, nil),
      system_value: local_assigns.fetch(:system_value, ""),
      var_names:,
      variables_json: var_names.to_json,
      var_labels: var_names.index_with { |name| "{{#{name}}}" },
    )
  end
end
