# frozen_string_literal: true

require "toml-rb"

module BuiltinAgents
  class DefinitionLoader
    DEFINITION_GLOBS = [
      Rails.root.join("config/builtin_agents/**/*.toml").to_s,
      Rails.root.join("plugins/**/config/builtin_agents/**/*.toml").to_s,
    ].freeze

    class << self
      def load_all
        paths = definition_paths
        signature = definition_signature(paths)
        return @cached_definitions if @cached_signature == signature && @cached_definitions

        definitions = paths.map { |path| load_file(Pathname.new(path)) }
        detect_duplicate_keys!(definitions)
        @cached_signature = signature
        @cached_definitions = definitions.sort_by(&:key).freeze
      end

      def load_for(keys)
        requested = Array(keys).map(&:to_s)
        load_all.select { |definition| definition.key.in?(requested) }
      end

      private

      def definition_paths
        DEFINITION_GLOBS.flat_map { |glob| Dir.glob(glob) }.sort
      end

      def definition_signature(paths)
        paths.map do |path|
          stat = File.stat(path)
          [path, stat.mtime.to_f, stat.size]
        rescue Errno::ENOENT
          [path, nil, nil]
        end
      end

      def load_file(path)
        data = TomlRB.parse(path.read).deep_stringify_keys

        BuiltinAgents::Definition.new(**definition_attributes(path, data))
      end

      def definition_attributes(path, data)
        identity_attributes(data)
          .merge(llm_attributes(data))
          .merge(runtime_attributes(data))
          .merge(source_path: path)
      end

      def identity_attributes(data)
        {
          key: data.fetch("key"),
          name: data.fetch("name"),
          description: data["description"],
          agent_type: data["agent_type"] || AgentConfiguration::DEFAULT_AGENT_TYPE,
          enabled: boolean_setting(data, "enabled", true),
          selectable: boolean_setting(data, "selectable", false),
        }
      end

      def llm_attributes(data)
        {
          temperature: (data["temperature"] || AgentConfiguration::DEFAULT_TEMPERATURE).to_f,
          thinking_effort: data["thinking_effort"],
          llm_config_source: data["llm_config_source"] || AgentConfiguration::DEFAULT_LLM_CONFIG_SOURCE,
          model_id: data["model_id"],
          llm_connector_id: data["llm_connector_id"],
        }
      end

      def runtime_attributes(data)
        {
          instructions: data["instructions"].to_s.delete_suffix("\n"),
          input_schema: data["input_schema"] || [],
          tool_keys: first_configured_value(data, "tools", "runtime_tool_keys"),
          subagent_keys: first_configured_value(data, "subagents", "subagent_builtin_keys"),
          skill_catalog_keys: first_configured_value(data, "skill_catalogs", "skill_catalog_keys"),
          capability_configs: normalize_capability_configs(data["capabilities"]),
        }
      end

      def first_configured_value(data, *keys)
        keys.each do |key|
          return data[key] if data.key?(key)
        end

        []
      end

      def boolean_setting(data, key, default)
        data.key?(key) ? data[key] : default
      end

      def normalize_capability_configs(raw)
        case raw
        when nil
          {}
        when Array
          raw.each_with_object({}) do |entry, configs|
            key, config = normalize_capability_entry(entry)
            configs[key] = config
          end
        when Hash
          raw.deep_stringify_keys.each_with_object({}) do |(key, value), configs|
            configs[key] = normalize_capability_value(key, value)
          end
        else
          raise ArgumentError, "Invalid builtin capabilities format: #{raw.class}"
        end
      end

      def normalize_capability_entry(entry)
        case entry
        when String, Symbol
          [entry.to_s, {}]
        when Hash
          data = entry.deep_stringify_keys
          key = data.delete("key").presence || data.delete("capability").presence
          raise ArgumentError, "Builtin capability entries must include `key`" if key.blank?

          [key, normalize_capability_value(key, data)]
        else
          raise ArgumentError, "Invalid builtin capability entry: #{entry.inspect}"
        end
      end

      def normalize_capability_value(key, value)
        case value
        when nil, true
          {}
        when false
          { "enabled" => false }
        when Hash
          value.deep_stringify_keys
        else
          raise ArgumentError, "Builtin capability '#{key}' must map to a table or boolean"
        end
      end

      def detect_duplicate_keys!(definitions)
        duplicate_keys = definitions.group_by(&:key).select { |_key, items| items.size > 1 }.keys
        return if duplicate_keys.empty?

        raise "Duplicate builtin agent keys detected: #{duplicate_keys.join(", ")}"
      end
    end
  end
end
