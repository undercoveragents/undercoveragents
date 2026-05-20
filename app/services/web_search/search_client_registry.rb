# frozen_string_literal: true

module WebSearch
  class SearchClientRegistry
    Definition = Data.define(:identifier, :class_name)

    class << self
      attr_reader :default_identifier

      def register(identifier, class_name, default: false)
        normalized_identifier = identifier.to_s
        normalized_class_name = class_name.to_s
        existing = definitions[normalized_identifier]

        if existing && existing.class_name != normalized_class_name
          raise ArgumentError, "Search client #{normalized_identifier.inspect} is already registered."
        end

        definitions[normalized_identifier] = Definition.new(
          identifier: normalized_identifier,
          class_name: normalized_class_name,
        )
        @default_identifier = normalized_identifier if default || @default_identifier.blank?
      end

      def fetch(identifier = nil)
        resolved_identifier = (identifier.presence || @default_identifier).to_s
        definition = definitions.fetch(resolved_identifier) do
          raise Error, "Unknown web search client: #{resolved_identifier.presence || "none"}."
        end

        definition.class_name.constantize.new
      end

      def registered?(identifier)
        definitions.key?(identifier.to_s)
      end

      def reset!
        @definitions = {}
        @default_identifier = nil
      end

      private

      def definitions
        @definitions ||= {}
      end
    end
  end
end
