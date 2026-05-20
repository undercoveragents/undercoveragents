# frozen_string_literal: true

module Admin
  class CloneRecordService
    CLONE_NAME_PREFIX = "Clone of "

    Result = Data.define(:record) do
      delegate :errors, to: :record

      def success?
        record.persisted?
      end
    end

    def self.call(record)
      new(record).call
    end

    def initialize(record)
      @record = record
    end

    def call
      clone = build_clone
      clone.save
      Result.new(clone)
    end

    private

    attr_reader :record

    def build_clone
      case record
      when Agent
        build_agent_clone
      when Tool
        build_tool_clone
      when Mission
        build_mission_clone
      else
        raise ArgumentError, "Unsupported record type: #{record.class.name}"
      end
    end

    def build_agent_clone
      record.dup.tap do |clone|
        clone.configuration = record.configuration.deep_dup
        clone.name = next_clone_name(record.operation.agents, record.name)
        clone[:builtin] = false
        clone.builtin = false
        clone.builtin_key = nil
        clone.builtin_source = nil
      end
    end

    def build_tool_clone
      record.dup.tap do |clone|
        clone.configuration = record.configuration.deep_dup
        clone.name = next_clone_name(record.operation.tools, record.name)
      end
    end

    def build_mission_clone
      record.dup.tap do |clone|
        clone.name = next_clone_name(record.operation.missions, record.name)
        clone.flow_data = record.flow_data.deep_dup
        clone.flow_undo_history = []
        clone.flow_redo_history = []
      end
    end

    def next_clone_name(scope, source_name)
      base_name = "#{CLONE_NAME_PREFIX}#{source_name}"
      candidate = base_name
      suffix = 2

      while scope.exists?(["LOWER(name) = ?", candidate.downcase])
        candidate = "#{base_name} (#{suffix})"
        suffix += 1
      end

      candidate
    end
  end
end
