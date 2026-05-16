# frozen_string_literal: true

# Provides the rag step plugin protocol for rag module configurators.
#
# Each plugin's configurator model includes this concern and implements:
#
# Class methods (metadata & params):
#   - key              → "sql_database_source"
#   - label            → "SQL Database"
#   - icon             → "fa-solid fa-database"
#   - stage            → :source / :chunking / :embedding / :storage
#   - description      → human-readable module description for selection cards
#   - permitted_params → strong params extraction
#   - build_from_params → factory for new instances
#
# Instance methods (behavior):
#   - execute(documents, context)    → processes documents, returns modified collection
#   - each_batch(context, &block)    → yields document batches (source modules)
#   - validate_configuration!        → raises if config is invalid for execution
#   - summary                        → one-line human-readable description
#   - form_partial_path → absolute path to the directory containing _form.html.haml
#     Default resolves to `plugins/<plugin>/app/views`.
module RagStepPlugin
  extend ActiveSupport::Concern

  VALID_STAGES = [:source, :chunking, :embedding, :storage].freeze

  Result = Data.define(:success?, :message)

  @type_map = {}
  @stage_map = {}
  @label_map = {}
  @icon_map = {}

  class << self
    def register(key, class_name, label:, icon:, stage:)
      registry_key = key.to_s
      klass_name = class_name.to_s
      stage_key = stage.to_sym

      raise ArgumentError, "Stage '#{stage}' is invalid" unless VALID_STAGES.include?(stage_key)

      if @type_map.key?(registry_key)
        existing_class = @type_map[registry_key]
        existing_stage = @stage_map[registry_key]
        return if existing_class == klass_name && existing_stage == stage_key

        raise ArgumentError, "Step type '#{registry_key}' is already registered"
      end

      @type_map[registry_key] = klass_name
      @stage_map[registry_key] = stage_key
      @label_map[registry_key] = label
      @icon_map[registry_key] = icon
    end

    def reset!
      @type_map = {}
      @stage_map = {}
      @label_map = {}
      @icon_map = {}
    end

    def type_map
      @type_map.dup
    end

    def stage_map
      @stage_map.dup
    end

    def resolve(key)
      class_name = @type_map[key.to_s]
      class_name&.constantize
    end

    def stage_for(key)
      @stage_map[key.to_s]
    end

    def modules_for_stage(stage_key)
      stage = stage_key.to_sym
      registry = UndercoverAgents::PluginSystem.registry

      @stage_map.select { |_k, v| v == stage }.keys.filter_map do |key|
        next unless registry.enabled?(key)

        klass = @type_map[key].constantize
        {
          key:,
          label: @label_map[key],
          icon: @icon_map[key],
          description: klass.description,
        }
      end
    end

    def type_keys
      @type_map.keys
    end
  end

  included do
    attr_accessor :_rag_step_record

    class << self
      def key(value = nil)
        return @key if value.nil?

        @key = value.to_s
      end

      def label(value = nil)
        return @label if value.nil?

        @label = value
      end

      def icon(value = nil)
        return @icon if value.nil?

        @icon = value
      end

      def stage(value = nil)
        return @stage if value.nil?

        @stage = value.to_sym
      end

      def description(value = nil)
        return @description || "" if value.nil?

        @description = value
      end
    end
  end

  def execute(_documents, _context)
    raise NotImplementedError, "#{self.class} must implement #execute"
  end

  def each_batch(context, &)
    docs = execute([], context)
    yield docs
  end

  def validate_configuration!; end

  delegate :label, to: :class

  def rag_step
    _rag_step_record
  end

  def rag_flow
    rag_step&.rag_flow
  end

  def step_tenant
    rag_flow&.operation&.tenant
  end

  def find_connector(connector_id)
    ConnectorLookup.find(connector_id, tenant: step_tenant)
  end

  def summary
    self.class.label
  end

  def form_partial_path
    model_file, = Object.const_source_location(self.class.name)
    model_file.sub(%r{/app/models/.*$}, "/app/views")
  end
end
