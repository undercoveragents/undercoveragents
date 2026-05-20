# frozen_string_literal: true

module RuntimeRecords
  AGENT_PERMITTED_ATTRIBUTES = [
    "name",
    "description",
    "instructions",
    "agent_type",
    "enabled",
    "selectable",
    "llm_config_source",
    "llm_connector_id",
    "model_id",
    "temperature",
    "thinking_effort",
    "thinking_budget",
    "custom_llm_params",
    "model_routing_config",
    "input_schema",
    "assigned_tool_ids",
    "subagent_ids",
    "skill_catalog_ids",
  ].freeze
  CHANNEL_PERMITTED_ATTRIBUTES = [
    "name",
    "channel_type",
    "description",
    "enabled",
    "default",
    "connector_id",
    "target_kind",
    "agent_id",
    "agent_ids",
    "mission_id",
    "mission_ids",
    "access_scope",
    "response_mode",
    "callback_url",
    *ClientConfiguration::CONTENT_FIELDS.map(&:to_s),
    *ClientConfiguration::LABEL_FIELDS.map(&:to_s),
    *ClientConfiguration::MESSAGE_ACTION_FIELDS.map(&:to_s),
  ].freeze
  TOOL_PERMITTED_ATTRIBUTES = [
    "tool_type",
    "name",
    "description",
    "enabled",
    "toolable_attributes",
  ].freeze
  TEST_SUITE_PERMITTED_ATTRIBUTES = [
    "name",
    "description",
    "suite_type",
    "agent_id",
    "mission_id",
    "evaluation_llm_connector_id",
    "evaluation_model_id",
    "evaluation_temperature",
  ].freeze
  AUTOMATION_TRIGGER_PERMITTED_ATTRIBUTES = [
    "name",
    "trigger_type",
    "enabled",
    "cron_expression",
    "timezone",
    "payload",
    "target_type",
    "target_id",
  ].freeze

  class Registry
    Definition = Data.define(
      :key,
      :label,
      :model_class,
      :permitted_attributes,
      :scope_resolver,
      :base_attributes,
      :clone_supported,
      :default_page,
      :page_resolver,
      :create_handler,
      :update_handler,
    ) do
      def initialize(**attributes)
        super(clone_supported: false, create_handler: nil, update_handler: nil, **attributes)
      end

      def scope_for(context)
        scope_resolver.call(context)
      end

      def base_attributes_for(context)
        raw_attributes = base_attributes.respond_to?(:call) ? base_attributes.call(context) : base_attributes
        raw_attributes.to_h.stringify_keys
      end

      def permitted_attribute_keys
        raw_attributes = permitted_attributes.respond_to?(:call) ? permitted_attributes.call : permitted_attributes
        Array(raw_attributes).map(&:to_s)
      end

      def default_page_for(record:, context:)
        return default_page.call(record:, context:) if default_page.respond_to?(:call)

        default_page
      end

      def path_for(page, record:, context:)
        page_resolver.call(page.to_s, record:, context:)
      end
    end

    class << self
      include RegistryAgentResources
      include RegistryAutomationTriggerResources
      include RegistryChannelAttributes
      include RegistryChannelResources
      include RegistryMissionResources
      include RegistrySkillCatalogResources
      include RegistryTestSuiteResources
      include RegistryToolResources

      def fetch(key)
        register_defaults!
        definitions.fetch(key.to_s) { raise KeyError, "Unknown resource '#{key}'." }
      end

      def definition_for_label(label)
        register_defaults!
        definitions.values.find { |definition| definition.label == label.to_s }
      end

      def definitions
        @definitions ||= {}
      end

      def register(key, **attributes)
        definitions[key.to_s] = Definition.new(key: key.to_s, **attributes)
      end

      def register_defaults!
        {
          "mission" => :register_mission,
          "agent" => :register_agent,
          "skill_catalog" => :register_skill_catalog,
          "test_suite" => :register_test_suite,
          "channel" => :register_channel,
          "tool" => :register_tool,
          "automation_trigger" => :register_automation_trigger,
        }.each do |key, method_name|
          send(method_name) unless definitions.key?(key)
        end
      end
    end
  end
end
