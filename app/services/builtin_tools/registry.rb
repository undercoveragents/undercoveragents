# frozen_string_literal: true

module BuiltinTools
  class Registry
    Definition = Data.define(
      :key,
      :name,
      :description,
      :visible_in_headquarter,
      :user_assignable,
      :configuration_hint,
      :runtime_name,
      :icon,
      :presentation,
      :compaction_policy,
      :factory,
    )

    class << self
      def register(key, name:, description:, **options, &factory)
        definitions[key.to_s] = Definition.new(
          key: key.to_s,
          name:,
          description:,
          visible_in_headquarter: options.fetch(:visible_in_headquarter, false),
          user_assignable: options.fetch(:user_assignable, false),
          configuration_hint: options[:configuration_hint],
          runtime_name: options[:runtime_name],
          icon: options[:icon],
          presentation: build_presentation(name:, icon: options[:icon], config: options[:tool_call_presentation]),
          compaction_policy: normalize_compaction_policy(options[:compaction_policy]),
          factory:,
        )
      end

      def build(key, **context)
        definition = definitions.fetch(key.to_s)
        definition.factory.call(**context)
      end

      def visible_definitions
        definitions.values.select(&:visible_in_headquarter).sort_by(&:name)
      end

      def user_assignable_definitions
        definitions.values.select(&:user_assignable).sort_by(&:name)
      end

      def user_assignable_keys
        user_assignable_definitions.map(&:key)
      end

      def definition_for(key)
        definitions[key.to_s]
      end

      def definition_for_runtime_name(runtime_name)
        runtime = runtime_name.to_s
        definitions.values.find { |definition| definition.runtime_name == runtime }
      end

      def definitions
        @definitions ||= {}
      end

      private

      def build_presentation(name:, icon:, config:)
        return if config.blank?

        ToolCalls::Presentation.new(display_name: name, icon:, **config)
      end

      def normalize_compaction_policy(value)
        return if value.nil?

        symbol = value.to_sym
        unless Chats::MessageCompactor::POLICIES.include?(symbol)
          raise ArgumentError, "Unknown compaction policy #{value.inspect}"
        end

        symbol
      end
    end
  end
end
