# frozen_string_literal: true

module AutomationTriggers
  class Dispatcher
    class InvalidPayload < StandardError; end

    def initialize(automation_trigger:, source:, payload: {})
      @automation_trigger = automation_trigger
      @payload = payload
      @source = source.to_s
    end

    def call
      result_record = dispatch_result_record!
      record_success!(result_record)
      result_record
    rescue StandardError => e
      record_failure!(e)
      raise
    end

    private

    attr_reader :automation_trigger, :payload, :source

    def schedulable
      automation_trigger.schedulable
    end

    def merged_payload
      automation_trigger.payload.deep_merge(normalized_payload)
    end

    def dispatch_result_record!
      case schedulable
      when Mission
        dispatch_mission!
      when RagFlow
        dispatch_rag_flow!
      else
        raise InvalidPayload, "Unsupported automation target '#{automation_trigger.schedulable_type}'."
      end
    end

    def dispatch_mission!
      filtered_payload = schedulable.filter_trigger_data(merged_payload)
      missing_inputs = schedulable.validate_required_inputs(filtered_payload)
      raise InvalidPayload, "Missing required fields: #{missing_inputs.join(", ")}" if missing_inputs.any?

      run = schedulable.mission_runs.create!(
        status: :pending,
        flow_snapshot: schedulable.flow_data,
        trigger_data: filtered_payload,
        execution_state: { "trigger" => trigger_metadata },
      )

      ::Api::MissionExecutionJob.perform_later(run.id, tenant_id: schedulable.operation.tenant_id)
      run
    end

    def dispatch_rag_flow!
      raise InvalidPayload, "RAG flow must be enabled to run." unless schedulable.runnable?
      raise InvalidPayload, "RAG flow must be fully configured to run." unless schedulable.fully_configured?

      run = schedulable.rag_runs.create!(
        status: :pending,
        triggered_by: rag_triggered_by,
        stats: rag_run_stats,
      )

      ::Rag::ExecutionJob.perform_later(
        schedulable.id,
        tenant_id: schedulable.operation.tenant_id,
        triggered_by: rag_triggered_by,
        run_id: run.id,
      )
      run
    end

    def record_success!(result_record)
      automation_trigger.update!(
        last_error: nil,
        last_triggered_at: Time.current,
        last_result_record: result_record,
      )
    end

    def record_failure!(error)
      automation_trigger.update(last_error: error.message)
    end

    def normalized_payload
      case payload
      when nil
        {}
      when ActionController::Parameters
        payload.to_unsafe_h.deep_stringify_keys
      when Hash
        payload.deep_stringify_keys
      else
        raise InvalidPayload, "Trigger payload must be a JSON object"
      end
    end

    def rag_triggered_by
      source == "schedule" ? "scheduled" : "webhook"
    end

    def rag_run_stats
      stats = { "trigger" => trigger_metadata }
      stats["payload"] = merged_payload if merged_payload.present?
      stats
    end

    def trigger_metadata
      {
        "automation_trigger_id" => automation_trigger.id,
        "name" => automation_trigger.name,
        "trigger_type" => automation_trigger.trigger_type,
        "source" => source,
        "schedulable_type" => automation_trigger.schedulable_type,
        "schedulable_id" => automation_trigger.schedulable_id,
      }
    end
  end
end
