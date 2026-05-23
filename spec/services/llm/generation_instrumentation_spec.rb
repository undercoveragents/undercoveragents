# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require "rails_helper"

RSpec.describe Llm::GenerationInstrumentation do
  def capture_event(event_name)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(event_name) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  describe ".instrument_generation" do
    it "emits metadata and token totals for successful turns" do
      model = create(:model, pricing: { "text_tokens" => { "standard" => { "input_per_million" => "1.0" } } })
      chat = create(:chat, model:)
      chat.define_singleton_method(:tools) { { lookup: Object.new } }

      capture_event(described_class::GENERATION_EVENT) do |events|
        result = described_class.instrument_generation(chat:, streaming: true) do
          expect(Current.llm_trace_id).to be_present
          create(
            :message,
            :assistant,
            chat:,
            model:,
            input_tokens: 10,
            output_tokens: 3,
            cached_tokens: 2,
            cache_creation_tokens: 1,
            thinking_tokens: 4,
          )
          :ok
        end

        payload = events.first.payload
        expect(result).to eq(:ok)
        expect(payload).to include(
          chat_id: chat.id,
          streaming: true,
          status: "success",
          tool_count: 1,
          message_count_before: 0,
          message_count_after: 1,
          input_tokens: 10,
          output_tokens: 3,
          cached_tokens: 2,
          cache_creation_tokens: 1,
          thinking_tokens: 4,
        )
        expect(payload[:trace_id]).to be_present
        expect(BigDecimal(payload[:cost])).to eq(BigDecimal("0.000016"))
      end
    end

    it "records errors and avoids nested generation events" do
      chat = create(:chat)
      create(:message, :user, chat:, content: "before")

      capture_event(described_class::GENERATION_EVENT) do |events|
        expect do
          described_class.instrument_generation(chat:, streaming: false) do
            raise ArgumentError, "bad prompt"
          end
        end.to raise_error(ArgumentError, "bad prompt")

        expect(events.first.payload).to include(status: "error", error_class: "ArgumentError")
      end

      capture_event(described_class::GENERATION_EVENT) do |events|
        result = Current.set(llm_trace_id: "trace-existing") do
          described_class.instrument_generation(chat:, streaming: false) { :nested }
        end

        expect(result).to eq(:nested)
        expect(events).to be_empty
      end
    end

    it "handles objects without tools when counting metadata" do
      chat_like = Struct.new(:id, :agent_id, :mission_id, :user_id, :execution_context, :parent_chat_id, :model) do
        def messages = Message.none
      end.new(nil, nil, nil, nil, nil, nil, nil)

      capture_event(described_class::GENERATION_EVENT) do |events|
        described_class.instrument_generation(chat: chat_like, streaming: false) { :ok }

        expect(events.first.payload).not_to have_key(:tool_count)
      end
    end
  end

  describe "metadata-only helper events" do
    it "instruments generation errors, tool calls, and stream chunks" do
      chat = create(:chat)
      message = create(:message, :assistant, chat:)
      tool_call = create(:tool_call, message:, tool_call_id: "call_1", name: "lookup")
      payloads = Hash.new { |hash, key| hash[key] = [] }
      subscribers = [
        described_class::GENERATION_ERROR_EVENT,
        described_class::TOOL_CALL_EVENT,
        described_class::STREAM_CHUNK_EVENT,
      ].map do |event_name|
        ActiveSupport::Notifications.subscribe(event_name) do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          payloads[event.name] << event.payload
        end
      end

      described_class.instrument_generation_error(chat: nil, error: RuntimeError.new("boom"))
      described_class.instrument_tool_call(
        chat:,
        tool_call:,
        metadata: {
          tool_call_id: "call_1",
          tool_name: "lookup",
        },
        duration_ms: 12,
      )
      described_class.instrument_stream_chunk(chat:, kind: :content, content: "hello")

      expect(payloads[described_class::GENERATION_ERROR_EVENT].first).to include(error_class: "RuntimeError")
      expect(payloads[described_class::TOOL_CALL_EVENT].first).to include(
        tool_call_record_id: tool_call.id,
        tool_call_id: "call_1",
        tool_name: "lookup",
        duration_ms: 12,
        status: "complete",
      )
      expect(payloads[described_class::STREAM_CHUNK_EVENT].first).to include(
        kind: "content",
        characters: 5,
        bytes: 5,
      )
    ensure
      subscribers&.each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
    end
  end
end

# rubocop:enable RSpec/ExampleLength
