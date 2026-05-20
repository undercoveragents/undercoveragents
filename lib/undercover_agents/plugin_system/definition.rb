# frozen_string_literal: true

module UndercoverAgents
  module PluginSystem
    # Holds metadata about a plugin.
    # Created by plugin.rb manifests via the DSL: UndercoverAgents::PluginSystem.register("id") { |p| ... }
    class Definition
      RAG_CATEGORY_TO_STAGE = {
        rag_input: :source,
        rag_chunking: :chunking,
        rag_embedding: :embedding,
        rag_storage: :storage,
      }.freeze
      RAG_CATEGORIES = RAG_CATEGORY_TO_STAGE.keys.freeze
      CONNECTOR_CATEGORIES = [:connector].freeze
      CAPABILITY_CATEGORIES = [:capability].freeze
      TOOL_CATEGORIES = [:tool].freeze
      CHANNEL_CATEGORIES = [:channel].freeze
      WEB_SEARCH_CATEGORIES = [:web_search].freeze
      NO_VALUE = Object.new

      attr_reader :identifier, :entry_points
      attr_accessor :root_path

      def initialize(identifier)
        @identifier = identifier.to_s
        @version = "0.1.0"
        @author = "Undercover Agents"
        @description = ""
        @icon = "fa-solid fa-puzzle-piece"
        @category = [:general]
        @entry_points = []
        @frozen = false
      end

      [:name, :version, :author, :description, :icon].each do |field|
        define_method(field) do |value = NO_VALUE|
          return instance_variable_get("@#{field}") if value.equal?(NO_VALUE)

          instance_variable_set("@#{field}", value)
        end

        define_method("#{field}=") do |value|
          instance_variable_set("@#{field}", value)
        end
      end

      def category(value = NO_VALUE)
        return @category if value.equal?(NO_VALUE)

        @category = normalize_categories(value)
      end

      def category=(value)
        @category = normalize_categories(value)
      end

      def add_rag_input(klass)
        add_entry_point(:rag_input, klass)
      end

      def add_rag_source(klass)
        add_rag_input(klass)
      end

      def add_rag_chunker(klass)
        add_entry_point(:rag_chunking, klass)
      end

      def add_rag_embedding(klass)
        add_entry_point(:rag_embedding, klass)
      end

      def add_rag_storage(klass)
        add_entry_point(:rag_storage, klass)
      end

      def add_connector(klass)
        add_entry_point(:connector, klass)
      end

      def add_capability(klass)
        add_entry_point(:capability, klass)
      end

      def add_tool(klass)
        add_entry_point(:tool, klass)
      end

      def add_channel(klass)
        add_entry_point(:channel, klass)
      end

      def add_web_search_client(klass, identifier: nil, default: false)
        add_entry_point(:web_search, klass, identifier:, default:)
      end

      def rag_step_entry_points
        entry_points.select { |entry| RAG_CATEGORIES.include?(entry.fetch(:category)) }
      end

      def rag_step_plugin?
        rag_step_entry_points.any? || category.map(&:to_sym).intersect?(RAG_CATEGORIES)
      end

      def connector_entry_points
        entry_points.select { |entry| CONNECTOR_CATEGORIES.include?(entry.fetch(:category)) }
      end

      def connector_plugin?
        connector_entry_points.any? || category.map(&:to_sym).intersect?(CONNECTOR_CATEGORIES)
      end

      def capability_entry_points
        entry_points.select { |entry| CAPABILITY_CATEGORIES.include?(entry.fetch(:category)) }
      end

      def capability_plugin?
        capability_entry_points.any? || category.map(&:to_sym).intersect?(CAPABILITY_CATEGORIES)
      end

      def tool_entry_points
        entry_points.select { |entry| TOOL_CATEGORIES.include?(entry.fetch(:category)) }
      end

      def tool_plugin?
        tool_entry_points.any? || category.map(&:to_sym).intersect?(TOOL_CATEGORIES)
      end

      def channel_entry_points
        entry_points.select { |entry| CHANNEL_CATEGORIES.include?(entry.fetch(:category)) }
      end

      def channel_plugin?
        channel_entry_points.any? || category.map(&:to_sym).intersect?(CHANNEL_CATEGORIES)
      end

      def web_search_entry_points
        entry_points.select { |entry| WEB_SEARCH_CATEGORIES.include?(entry.fetch(:category)) }
      end

      def web_search_plugin?
        web_search_entry_points.any? || category.map(&:to_sym).intersect?(WEB_SEARCH_CATEGORIES)
      end

      def only_tool_plugin?
        tool_plugin? && !rag_step_plugin? && !connector_plugin? && !channel_plugin?
      end

      def freeze!
        @frozen = true
        self
      end

      def frozen?
        @frozen
      end

      # root_path can be set even after freeze (set by Loader after registration)

      def engine_module_name
        "UndercoverAgents::Plugins::#{identifier.camelize}Engine"
      end

      def to_h
        {
          identifier:,
          name:,
          version:,
          author:,
          description:,
          icon:,
          category:,
          entry_points:,
          root_path: root_path&.to_s,
        }
      end

      private

      def add_entry_point(category_key, klass, **attributes)
        entry = { category: category_key, class_name: klass.to_s }.merge(attributes.compact)
        entry[:stage] = RAG_CATEGORY_TO_STAGE.fetch(category_key) if RAG_CATEGORY_TO_STAGE.key?(category_key)
        @entry_points << entry
      end

      def normalize_categories(value)
        Array(value).flatten.compact.map(&:to_sym)
      end
    end
  end
end
