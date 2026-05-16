# frozen_string_literal: true

module Tools
  class RuntimeBuilder
    class << self
      def build(tool_record, agent: nil, parent_chat: nil)
        new(tool_record, agent:, parent_chat:).build
      end

      def build_many(tool_records, agent: nil, parent_chat: nil)
        Array(tool_records).flat_map do |tool_record|
          Array(build(tool_record, agent:, parent_chat:)).compact
        end
      end
    end

    def initialize(tool_record, agent:, parent_chat:)
      @tool_record = tool_record
      @agent = agent
      @parent_chat = parent_chat
    end

    def build
      tool_class = tool_plugin_class
      return nil unless tool_class.respond_to?(:build_runtime_tool)

      tool_class.build_runtime_tool(tool_record, agent:, parent_chat:)
    rescue StandardError => e
      Rails.logger.error "[Tools::RuntimeBuilder] Failed to build tool '#{tool_name}': #{e.message}"
      nil
    end

    private

    attr_reader :tool_record, :agent, :parent_chat

    def tool_type
      if tool_record.respond_to?(:tool_type)
        tool_record.tool_type
      elsif tool_record.respond_to?(:toolable_type)
        ToolPlugin.filter_type(tool_record.toolable_type)
      end
    end

    def tool_name
      tool_record.respond_to?(:name) ? tool_record.name : "unknown"
    end

    def tool_plugin_class
      ToolPlugin.resolve(tool_type)
    end
  end
end
