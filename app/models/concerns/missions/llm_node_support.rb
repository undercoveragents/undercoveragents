# frozen_string_literal: true

module Missions
  # Shared behavior for mission nodes that call an LLM (Generate Text, Generate Image).
  # Provides connector/model resolution, chat building, prompt handling, file attachment
  # resolution, and error helpers.
  module LlmNodeSupport
    extend ActiveSupport::Concern

    private

    def failure(message)
      Missions::NodeResult.new(status: :failure, output: message)
    end

    # Returns the user-facing input from context: prefers the current branch input,
    # then the explicit input variable. Nil when the node is first.
    def resolve_user_input(context)
      current_input = context.current_input
      return current_input.to_s.presence unless file_variable?(current_input)

      context.get_variable("input")&.to_s.presence
    end

    def resolve_connector(node_data, context: nil)
      mission = context&.mission_run&.mission
      tenant = mission&.operation&.tenant
      return nil if tenant.blank?

      ConnectorLookup.find(node_data["connector_id"], tenant:)
    end

    def build_llm_chat(runtime_config, node_data, context)
      node_label = node_data["label"].presence || node_data["name"].presence || self.class.node_label
      chat = Chat.create!(
        model: runtime_config.model_record,
        title: "#{context.mission_run.mission.name} — #{node_label}",
        execution_context: :mission,
      )
      chat.context = runtime_config.connector.build_context
      apply_llm_node_options(chat, runtime_config, node_data)
      attach_llm_node_model_routing(chat, runtime_config, node_data)
      chat
    end

    def apply_llm_node_options(chat, runtime_config, node_data)
      Llm::ChatOptions.apply_to_chat(
        chat:,
        model_id: runtime_config.model_id,
        model_record: runtime_config.model_record,
        tools_present: llm_node_tools_present?(node_data),
        temperature: runtime_config.temperature,
        thinking_effort: runtime_config.thinking_effort,
        thinking_budget: runtime_config.thinking_budget,
        custom_params: runtime_config.custom_params,
      )
    end

    def attach_llm_node_model_routing(chat, runtime_config, node_data)
      routing_config = runtime_config.model_routing_config
      return if Llm::ModelRoutingConfig.persistable(routing_config).blank?

      chat.configure_model_routing!(
        primary_connector: runtime_config.connector,
        primary_model_id: runtime_config.model_id,
        primary_model_record: runtime_config.model_record,
        routing_config:,
        temperature: runtime_config.temperature,
        thinking_effort: runtime_config.thinking_effort,
        thinking_budget: runtime_config.thinking_budget,
        custom_params: runtime_config.custom_params,
        tools_present: llm_node_tools_present?(node_data),
      )
    end

    def apply_system_instructions(chat, system_prompt, user_input)
      return unless system_prompt.present? && user_input.present?

      chat.with_instructions(system_prompt)
    end

    def ask_message(system_prompt, user_input)
      system_prompt.present? && user_input.present? ? user_input : (system_prompt.presence || user_input.to_s)
    end

    def validate_connector_and_model(node_data, context:)
      return source_aware_llm_config(node_data, context:) if source_aware_llm_node?

      connector = resolve_connector(node_data, context:)
      return [nil, nil, failure("LLM connector not configured")] unless connector

      model = node_data["model"]
      return [nil, nil, failure("LLM model not configured")] if model.blank?

      [direct_llm_config(connector, model, node_data), model, nil]
    end

    def source_aware_llm_node?
      self.class.respond_to?(:node_type) && self.class.node_type == "llm"
    end

    def source_aware_llm_config(node_data, context:)
      runtime_config, error = Missions::LlmNodeRuntimeConfig.resolve(node_data:, context:)
      return [nil, nil, failure(error)] if error

      [runtime_config, runtime_config.model_id, nil]
    end

    def direct_llm_config(connector, model, node_data)
      Missions::LlmNodeRuntimeConfig::Resolved.new(
        source: "node",
        connector:,
        model_id: model,
        model_record: Llm::ChatOptions.resolve_model(model),
        temperature: node_data["temperature"] || SystemPreference::DEFAULT_TEMPERATURE,
        thinking_effort: node_data["thinking_effort"],
        thinking_budget: node_data["thinking_budget"],
        custom_params: node_data["custom_llm_params"],
        model_routing_config: node_data["model_routing_config"],
      )
    end

    # ── File attachment helpers ──

    # Checks whether a value looks like a file metadata hash (from input node,
    # generate image, or write file nodes).
    def file_variable?(value)
      value.is_a?(Hash) && value["blob_id"].present? && value["filename"].present?
    end

    # Resolves file attachments from the configured file_variables list and
    # auto-detected file values from the current branch input. Returns an array of
    # tempfile paths suitable for RubyLLM's `with:` parameter.
    def resolve_file_attachments(context, node_data)
      file_values = collect_file_values(context, node_data)
      return [] if file_values.empty?

      file_values.filter_map { |meta| download_blob_to_tempfile(meta) }
    end

    # Collects file metadata hashes from explicitly configured variables and
    # the current branch input payload.
    def collect_file_values(context, node_data)
      values = []

      # Explicitly configured file variables
      (node_data["file_variables"] || []).each do |var_name|
        val = context.get_variable(var_name)
        values.concat(normalize_file_values(val))
      end

      values.concat(normalize_file_values(context.current_input))

      values.uniq { |v| v["blob_id"] }
    end

    def normalize_file_values(value)
      return [] if value.nil?
      return [value] if file_variable?(value)
      return value.select { |v| file_variable?(v) } if value.is_a?(Array)

      []
    end

    def download_blob_to_tempfile(meta)
      blob = ActiveStorage::Blob.find_by(id: meta["blob_id"])
      return nil unless blob

      ext = File.extname(blob.filename.to_s)
      tmpfile = Tempfile.new(["mission_file_", ext])
      tmpfile.binmode
      blob.download { |chunk| tmpfile.write(chunk) }
      tmpfile.rewind
      tmpfile.path
    end

    def llm_node_tools_present?(node_data)
      Array(node_data["tool_ids"]).filter_map { |value| Integer(value, exception: false) }.any?
    end
  end
end
