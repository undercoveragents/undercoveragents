# frozen_string_literal: true

require "fileutils"
require "json"

# rubocop:disable Metrics/ModuleLength
module UndercoverAgents
  module RubyLlmDebugLogging
    ENABLED = false
    LOG_PATH = Rails.root.join("log/llm_api_debug.log")
    REDACTED = "[FILTERED]"
    DATA_URL_PATTERN = /\Adata:[^;,]+;base64,/i
    MAX_DEPTH = 8
    SEPARATOR = "=" * 100
    SENSITIVE_KEY_PATTERN = /(authorization|api[-_]?key|token|secret|password)/i
    MUTEX = Mutex.new

    module ProviderPatch
      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      def complete(messages, tools:, temperature:, model:, params: {}, headers: {}, schema: nil, thinking: nil,
                   tool_prefs: nil, &block)
        UndercoverAgents::RubyLlmDebugLogging.capture_chat_request(
          provider: self,
          model:,
          messages:,
          tools:,
          temperature:,
          params:,
          headers:,
          schema:,
          thinking:,
          tool_prefs:,
          streaming: block_given?,
        ) do
          build_chat_payload(
            messages:,
            tools:,
            temperature:,
            model:,
            params:,
            schema:,
            thinking:,
            tool_prefs:,
            streaming: block_given?,
          )
        end

        super
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      def embed(text, model:, dimensions:)
        UndercoverAgents::RubyLlmDebugLogging.capture_embedding_request(
          provider: self,
          model:,
          text:,
          dimensions:,
        ) do
          render_embedding_payload(text, model:, dimensions:)
        end

        super
      end

      def paint(prompt, model:, size:, **)
        UndercoverAgents::RubyLlmDebugLogging.capture_image_request(
          provider: self,
          model:,
          prompt:,
          size:,
          **,
        ) do
          render_image_payload(prompt, model:, size:, **)
        end

        super
      end

      private

      # rubocop:disable Metrics/ParameterLists
      def build_chat_payload(messages:, tools:, temperature:, model:, params:, schema:, thinking:, tool_prefs:,
                             streaming:)
        normalized_temperature = maybe_normalize_temperature(temperature, model)
        payload = RubyLLM::Utils.deep_merge(
          render_payload(
            messages,
            tools:,
            tool_prefs:,
            temperature: normalized_temperature,
            model:,
            stream: streaming,
            schema:,
            thinking:,
          ),
          params,
        )

        { payload:, normalized_temperature: }
      end
      # rubocop:enable Metrics/ParameterLists
    end

    class << self
      def enabled?
        ENABLED
      end

      # rubocop:disable Metrics/ParameterLists
      def capture_chat_request(provider:, model:, messages:, tools:, temperature:, params:, headers:, schema:,
                               thinking:, tool_prefs:, streaming:)
        return unless enabled?

        debug_data = yield
        lines = [header_line(kind: "chat", provider:, model:, extra: { streaming:, chat_id: current_chat_id })]
        append_json_section(lines, "Requested Temperature", temperature)
        append_json_section(lines, "Temperature", debug_data[:normalized_temperature])
        append_json_section(lines, "Thinking", thinking)
        append_json_section(lines, "Tool Preferences", tool_prefs)
        append_messages_section(lines, messages)
        append_json_section(lines, "Tools", tool_payloads(tools))
        append_json_section(lines, "Custom Params", params)
        append_json_section(lines, "Headers", headers)
        append_json_section(lines, "Schema", schema)
        append_json_section(lines, "Provider Payload", debug_data[:payload])
        write_entry(lines)
      rescue StandardError => e
        log_failure("chat request", e)
      end
      # rubocop:enable Metrics/ParameterLists

      def capture_embedding_request(provider:, model:, text:, dimensions:)
        return unless enabled?

        lines = [header_line(kind: "embedding", provider:, model:, extra: { chat_id: current_chat_id })]
        append_text_section(lines, "Text", text)
        append_json_section(lines, "Dimensions", dimensions)
        append_json_section(lines, "Provider Payload", yield)
        write_entry(lines)
      rescue StandardError => e
        log_failure("embedding request", e)
      end

      def capture_image_request(provider:, model:, prompt:, size:, **options)
        return unless enabled?

        attachments = options[:with]
        mask = options[:mask]
        params = options[:params]
        lines = [header_line(kind: "image", provider:, model:, extra: { chat_id: current_chat_id })]
        append_text_section(lines, "Prompt", prompt)
        append_json_section(lines, "Size", size)
        append_json_section(lines, "With", attachments) if attachments.present?
        append_json_section(lines, "Mask", mask) if mask.present?
        append_json_section(lines, "Custom Params", params) if params.present?
        append_json_section(lines, "Provider Payload", yield)
        write_entry(lines)
      rescue StandardError => e
        log_failure("image request", e)
      end

      private

      def write_entry(lines)
        entry = ([SEPARATOR] + Array(lines) + [SEPARATOR, nil]).join("\n")
        log_path = resolved_log_path
        FileUtils.mkdir_p(log_path.dirname)

        MUTEX.synchronize do
          File.open(log_path, "a") { |file| file.write(entry) }
        end
      end

      def resolved_log_path
        chat_id = current_chat_id
        return LOG_PATH if chat_id.blank?

        extension = LOG_PATH.extname
        basename = LOG_PATH.basename(extension).to_s
        LOG_PATH.dirname.join("#{basename}_chat_#{chat_id}#{extension}")
      end

      def current_chat_id
        chat = Current.chat
        chat_id = chat.respond_to?(:id) ? chat.id : chat
        chat_id.presence
      end

      def append_messages_section(lines, messages)
        lines << "Messages:"

        if Array(messages).empty?
          lines << "  (none)"
          return
        end

        Array(messages).each_with_index do |message, index|
          lines.concat(message_lines(message, index + 1))
        end
      end

      def message_lines(message, index)
        role = safe_message_attribute(message, :role)
        tool_call_id = safe_message_attribute(message, :tool_call_id)
        tool_calls = safe_message_attribute(message, :tool_calls)
        lines = ["  #{index}. role=#{role}"]
        lines.last << " tool_call_id=#{tool_call_id}" if tool_call_id.present?

        content = safe_message_attribute(message, :content)
        lines.concat(indented_lines(format_text_block(content), indent: 4))

        return lines if tool_calls.blank?

        lines << "    tool_calls:"
        lines.concat(indented_lines(pretty_json(tool_calls), indent: 6))
        lines
      end

      def append_text_section(lines, title, value)
        return if value.nil?

        lines << "#{title}:"
        lines.concat(indented_lines(format_text_block(value), indent: 2))
      end

      def append_json_section(lines, title, value)
        return if value.nil?
        return if value.respond_to?(:empty?) && value.empty?

        lines << "#{title}:"
        lines.concat(indented_lines(pretty_json(value), indent: 2))
      end

      def indented_lines(text, indent:)
        prefix = " " * indent
        text.to_s.lines(chomp: true).map { |line| "#{prefix}#{line}" }
      end

      def format_text_block(value)
        sanitized = sanitize_value(value)
        return sanitized if sanitized.is_a?(String)

        pretty_json(sanitized)
      end

      def pretty_json(value)
        JSON.pretty_generate(sanitize_value(value))
      rescue JSON::GeneratorError, TypeError
        sanitize_value(value).to_s
      end

      def tool_payloads(tools)
        Array(tools.to_h.values).map { |tool| sanitize_tool(tool) }
      rescue StandardError
        sanitize_value(tools)
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      def sanitize_value(value, depth: 0)
        return "[max depth reached]" if depth >= MAX_DEPTH

        case value
        when nil, Numeric, TrueClass, FalseClass
          value
        when Symbol
          value.to_s
        when String
          sanitize_string(value)
        when Array
          value.map { |item| sanitize_value(item, depth: depth + 1) }
        when Hash
          sanitize_hash(value, depth: depth + 1)
        else
          return sanitize_tool(value) if value.is_a?(RubyLLM::Tool)

          sanitize_object(value, depth: depth + 1)
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      def sanitize_hash(hash, depth:)
        hash.each_with_object({}) do |(key, value), acc|
          key_string = key.to_s
          acc[key_string] = sensitive_key?(key_string) ? REDACTED : sanitize_value(value, depth:)
        end
      end

      def sanitize_object(value, depth:)
        hash_like = safe_hash_like(value)
        return sanitize_value(hash_like, depth:) if hash_like

        value.to_s
      end

      def safe_hash_like(value)
        return value.to_h if value.respond_to?(:to_h)

        return value.instance_values if value.respond_to?(:instance_values) && value.instance_values.present?

        nil
      rescue StandardError
        nil
      end

      def sanitize_tool(tool)
        {
          name: tool.name,
          description: tool.description,
          params_schema: sanitize_value(tool.params_schema),
          provider_params: sanitize_value(tool.provider_params),
        }.compact
      end

      def sanitize_string(value)
        return data_url_placeholder(value) if value.match?(DATA_URL_PATTERN)

        value
      end

      def data_url_placeholder(value)
        prefix, encoded = value.split(",", 2)
        mime_type = prefix.delete_prefix("data:").delete_suffix(";base64")
        "[omitted data URL #{mime_type}, #{encoded.to_s.length} encoded chars]"
      end

      def sensitive_key?(key)
        key.to_s.match?(SENSITIVE_KEY_PATTERN)
      end

      def safe_message_attribute(message, attribute)
        return unless message.respond_to?(attribute)

        message.public_send(attribute)
      rescue StandardError
        nil
      end

      def header_line(kind:, provider:, model:, extra: {})
        fields = {
          kind:,
          provider: provider_identifier(provider),
          model: model_identifier(model),
          pid: Process.pid,
        }.merge(extra.compact)

        timestamp = Time.current.utc.iso8601(6)
        "[#{timestamp}] #{fields.map { |key, value| "#{key}=#{value}" }.join(" ")}"
      end

      def provider_identifier(provider)
        provider.respond_to?(:slug) ? provider.slug : provider.class.name
      end

      def model_identifier(model)
        return model.id if model.respond_to?(:id)
        return model.model_id if model.respond_to?(:model_id)

        model.to_s
      end

      def log_failure(kind, error)
        Rails.logger.warn("[RubyLlmDebugLogging] Failed to write #{kind}: #{error.message}")
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
