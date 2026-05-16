# frozen_string_literal: true

module Missions
  class FieldContract
    KINDS = [
      :literal,
      :template,
      :formula,
      :collection_ref,
      :assignment_map,
      :input_fields,
      :output_selection,
      :id_ref,
      :enum,
    ].freeze

    attr_reader :key, :kind, :value_type, :description

    def initialize(key:, **options)
      @key = key.to_s
      @kind = options.fetch(:kind, :literal).to_sym
      @value_type = options.fetch(:value_type, :any).to_sym
      @description = options.fetch(:description, "").to_s
      @required = options.fetch(:required, false) ? true : false
      @json = options.fetch(:json, false) ? true : false

      raise ArgumentError, "Unknown field contract kind: #{@kind}" unless KINDS.include?(@kind)

      freeze
    end

    def required?
      @required
    end

    def json?
      @json
    end

    def template?
      @kind == :template
    end

    def formula?
      @kind == :formula
    end

    def collection_reference?
      @kind == :collection_ref
    end

    def assignment_map?
      @kind == :assignment_map
    end

    def input_fields?
      @kind == :input_fields
    end

    def reference_scannable?
      template? || formula? || assignment_map?
    end

    def to_h
      {
        key:,
        kind:,
        value_type:,
        description:,
        required: required?,
        json: json?,
      }
    end
  end
end
