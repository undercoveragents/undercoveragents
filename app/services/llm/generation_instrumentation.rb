# frozen_string_literal: true

module Llm
  class GenerationInstrumentation
    GENERATION_EVENT = "llm.generation.undercover_agents"
    GENERATION_ERROR_EVENT = "llm.generation_error.undercover_agents"
    TOOL_CALL_EVENT = "llm.tool_call.undercover_agents"
    STREAM_CHUNK_EVENT = "llm.stream_chunk.undercover_agents"

    def self.instrument_generation(chat:, streaming:, &)
      return yield if Current.llm_trace_id.present?

      trace_id = SecureRandom.uuid
      before_max_id = chat.messages.maximum(:id)
      payload = generation_payload(chat, trace_id, streaming)
      started_at = monotonic_now

      Current.set(llm_trace_id: trace_id) do
        ActiveSupport::Notifications.instrument(GENERATION_EVENT, payload) do
          run_generation(chat, payload, before_max_id, started_at, &)
        end
      end
    end

    def self.instrument_generation_error(chat:, error:)
      ActiveSupport::Notifications.instrument(
        GENERATION_ERROR_EVENT,
        base_payload(chat).merge(trace_id: Current.llm_trace_id, **error_payload(error)),
      )
    end

    def self.instrument_tool_call(chat:, tool_call:, metadata:, duration_ms:, status: "complete")
      ActiveSupport::Notifications.instrument(
        TOOL_CALL_EVENT,
        base_payload(chat).merge(
          trace_id: Current.llm_trace_id,
          tool_call_record_id: tool_call&.id,
          tool_call_id: metadata[:tool_call_id],
          tool_name: metadata[:tool_name],
          duration_ms:,
          status:,
        ),
      )
    end

    def self.instrument_stream_chunk(chat:, kind:, content:)
      text = content.to_s
      ActiveSupport::Notifications.instrument(
        STREAM_CHUNK_EVENT,
        base_payload(chat).merge(
          trace_id: Current.llm_trace_id,
          kind: kind.to_s,
          characters: text.length,
          bytes: text.bytesize,
        ),
      )
    end

    def self.base_payload(chat)
      model = payload_value(chat, :model)
      {
        chat_id: payload_value(chat, :id),
        agent_id: payload_value(chat, :agent_id),
        mission_id: payload_value(chat, :mission_id),
        user_id: payload_value(chat, :user_id),
        execution_context: payload_value(chat, :execution_context),
        parent_chat_id: payload_value(chat, :parent_chat_id),
        model_id: payload_value(model, :model_id),
        provider: payload_value(model, :provider),
      }.compact
    end
    private_class_method :base_payload

    def self.payload_value(record, method_name)
      record.public_send(method_name) if record.respond_to?(method_name)
    end
    private_class_method :payload_value

    def self.generation_payload(chat, trace_id, streaming)
      base_payload(chat).merge(
        trace_id:,
        streaming:,
        status: "running",
        tool_count: tool_count(chat),
        message_count_before: chat.messages.count,
      ).compact
    end
    private_class_method :generation_payload

    def self.run_generation(chat, payload, before_max_id, started_at)
      result = yield
      payload[:status] = "success"
      result
    rescue StandardError => e
      payload.merge!(error_payload(e))
      raise
    ensure
      payload.merge!(completion_payload(chat, before_max_id, started_at))
    end
    private_class_method :run_generation

    def self.completion_payload(chat, before_max_id, started_at)
      messages = messages_after(chat, before_max_id)
      {
        duration_ms: elapsed_ms(started_at),
        message_count_after: chat.messages.count,
        input_tokens: sum_messages(messages, :input_tokens),
        output_tokens: sum_messages(messages, :output_tokens),
        cached_tokens: sum_messages(messages, :cached_tokens),
        cache_creation_tokens: sum_messages(messages, :cache_creation_tokens),
        thinking_tokens: sum_messages(messages, :thinking_tokens),
        cost: sum_message_cost(messages).to_s,
      }
    end
    private_class_method :completion_payload

    def self.sum_messages(messages, method_name)
      messages.sum { |message| message.public_send(method_name).to_i }
    end
    private_class_method :sum_messages

    def self.sum_message_cost(messages)
      messages.sum { |message| message.calculate_cost || 0 }
    end
    private_class_method :sum_message_cost

    def self.messages_after(chat, before_max_id)
      scope = chat.messages.order(:id)
      scope = scope.where("id > ?", before_max_id) if before_max_id
      scope.to_a
    end
    private_class_method :messages_after

    def self.error_payload(error)
      {
        status: "error",
        error_class: error.class.name,
        error_message: error.message,
      }
    end
    private_class_method :error_payload

    def self.tool_count(chat)
      return unless chat.respond_to?(:tools)

      chat.tools.size
    end
    private_class_method :tool_count

    def self.monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :monotonic_now

    def self.elapsed_ms(started_at)
      ((monotonic_now - started_at) * 1000).round
    end
    private_class_method :elapsed_ms
  end
end
