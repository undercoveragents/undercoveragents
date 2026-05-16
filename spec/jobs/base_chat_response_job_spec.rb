# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaseChatResponseJob do
  subject(:job) { job_class.new }

  let(:job_class) do
    Class.new(described_class) do
      public :setup_tool_broadcasting, :broadcast_chunk, :broadcast_tool_event, :broadcast_error_message,
             :finalize_chat
      public :advance_stream_phase, :append_stream_content, :persist_stream_content, :stream_phase_for
    end
  end

  let(:chat) do
    instance_double(
      Chat,
      id: 123,
      stream_channel_name: "chat_stream_123",
      ui_stream_channel_name: "chat_stream_123",
      cancelled?: false,
      idle!: true,
      broadcast_status_update: true,
    )
  end

  let(:metadata) do
    instance_double(
      ToolCalls::Presentation,
      display_name: "Tool Search",
      icon: "fa-search",
    )
  end

  def build_transient_chat(message)
    Object.new.tap { |chat| chat.instance_variable_set(:@message, message) }
  end

  def build_persisted_message(content: "")
    Class.new do
      attr_accessor :content
      attr_reader :updates

      def initialize(initial_content)
        @content = initial_content
        @updates = 0
      end

      def persisted?
        true
      end

      def update!(attributes)
        @content = attributes.fetch(:content)
        @updates += 1
      end
    end.new(content)
  end

  def build_stream_chat(id: 456, parent_chat_id: nil, agent_name: nil)
    ui_chat = instance_double(
      Chat,
      id:,
      ui_stream_channel_name: "chat_user_stream_#{id}",
    )

    allow(ui_chat).to receive(:ui_stream_payload) do |payload|
      payload.merge({ parent_chat_id:, agent_name: }.compact)
    end

    ui_chat
  end

  before do
    allow(chat).to receive(:ui_stream_payload) { |payload| payload }
  end

  def expect_tool_event_broadcast(event, widget_payload)
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(type: "tool_event", chat_id: 123, event:, widget_payload:),
    )
  end

  describe "#setup_tool_broadcasting" do
    let(:tool_call) { instance_double(ToolCall, id: 101, tool_call_id: "call-1", name: "tool.search") }
    let(:callbacks) { {} }

    before do
      allow(chat).to receive(:before_tool_call_execution) { |&block| callbacks[:start] = block }
      allow(chat).to receive(:after_tool_call_execution) { |&block| callbacks[:complete] = block }
      allow(ToolCalls::DisplayMetadataResolver).to receive(:resolve).and_return(metadata)
      allow(metadata).to receive(:sample_phrase).with(status: :running).and_return("Searching")
      allow(metadata).to receive(:sample_phrase).with(status: :complete).and_return("Done")
      allow(metadata).to receive(:widget_payload).with(status: :running, phrase: "Searching").and_return({})
      allow(metadata).to receive(:widget_payload).with(status: :complete, phrase: "Done").and_return({})
      allow(ActionCable.server).to receive(:broadcast)

      job.setup_tool_broadcasting(chat)
    end

    it "broadcasts a tool start event through the registered callback" do
      callbacks[:start].call(tool_call)

      expect(chat).to have_received(:broadcast_status_update).with(phase: nil)
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "tool_event",
          chat_id: 123,
          event: "start",
          tool_call_id: "call-1",
        ),
      )
    end

    it "broadcasts a tool completion event through the registered callback" do
      callbacks[:complete].call("call-1", "tool.search", 120)

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "tool_event", chat_id: 123, event: "complete"),
      )
    end
  end

  describe "#streamed_tool_call_id" do
    it "returns the available runtime identifier" do
      fallback_only = Struct.new(:id).new(101)
      runtime_identifier = Struct.new(:id, :tool_call_id).new(101, "call-1")

      expect(job.send(:streamed_tool_call_id, nil)).to be_nil
      expect(job.send(:streamed_tool_call_id, fallback_only)).to eq(101)
      expect(job.send(:streamed_tool_call_id, runtime_identifier)).to eq("call-1")
    end
  end

  describe "#broadcast_chunk" do
    it "extracts text from hashes with a symbol text key" do
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(chat, { text: "pondering" }, kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "chunk", chat_id: 123, content: "pondering", kind: "thinking"),
      )
    end

    it "extracts text from hashes with a string text key" do
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(chat, { "text" => "pondering" }, kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "chunk", chat_id: 123, content: "pondering", kind: "thinking"),
      )
    end

    it "falls back to the hash string when no text key is present" do
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(chat, { signature: "sig" }, kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "chunk", chat_id: 123, content: "{signature: \"sig\"}", kind: "thinking"),
      )
    end

    it "extracts text from RubyLLM thinking objects" do
      thinking = Struct.new(:text, :signature).new("pondering", "sig")
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(chat, thinking, kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "chunk", chat_id: 123, content: "pondering", kind: "thinking"),
      )
    end

    it "extracts text from RubyLLM thinking objects for child streams" do
      thinking = Struct.new(:text, :signature).new("pondering", "sig")
      stream_chat = build_stream_chat
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(stream_chat, thinking, kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        stream_chat.ui_stream_channel_name,
        hash_including(
          type: "chunk",
          chat_id: 456,
          content: "pondering",
          kind: "thinking",
        ),
      )
    end

    it "broadcasts chunks with a chunk kind" do
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(chat, "pondering", kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "chunk", chat_id: 123, content: "pondering", kind: "thinking"),
      )
    end

    it "broadcasts child chunks with a chunk kind" do
      stream_chat = build_stream_chat
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(stream_chat, "pondering", kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        stream_chat.ui_stream_channel_name,
        hash_including(
          type: "chunk",
          chat_id: 456,
          content: "pondering",
          kind: "thinking",
        ),
      )
    end

    it "returns early when content is blank" do
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(chat, "")

      expect(ActionCable.server).not_to have_received(:broadcast)
    end
  end

  describe "#broadcast_tool_event" do
    let(:stream_chat) do
      build_stream_chat
    end

    let(:stream_widget_payload) do
      {
        state: "running",
        tool_widget_group_title_value: "Working on the mission flow",
      }
    end

    before do
      allow(ToolCalls::DisplayMetadataResolver).to receive(:resolve).and_return(metadata)
      allow(metadata).to receive(:sample_phrase).with(status: :running).and_return("Searching")
      allow(metadata).to receive(:sample_phrase).with(status: :complete).and_return("Done")
      allow(metadata).to receive(:widget_payload)
        .with(status: :running, phrase: "Searching")
        .and_return(stream_widget_payload)
      allow(metadata).to receive(:widget_payload)
        .with(status: :complete, phrase: "Done")
        .and_return({ state: "complete", tool_widget_group_title_value: "Working on the mission flow" })
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "broadcasts both running and complete tool event payloads" do
      job.broadcast_tool_event(chat, "start", "call-1", "tool.search")
      job.broadcast_tool_event(chat, "complete", "call-1", "tool.search")

      expect(ToolCalls::DisplayMetadataResolver).to have_received(:resolve).twice
      expect_tool_event_broadcast("start", stream_widget_payload)
      expect_tool_event_broadcast(
        "complete",
        hash_including(tool_widget_group_title_value: "Working on the mission flow"),
      )
    end

    it "broadcasts child tool events over ActionCable" do
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_tool_event(stream_chat, "start", "call-1", "tool.search")

      expect(ActionCable.server).to have_received(:broadcast).with(
        stream_chat.ui_stream_channel_name,
        hash_including(
          type: "tool_event",
          chat_id: 456,
          event: "start",
          tool_call_id: "call-1",
          tool_name: "tool.search",
          display_name: "Tool Search",
          icon: "fa-search",
          widget_payload: stream_widget_payload,
        ),
      )
    end
  end

  describe "#broadcast_error_message" do
    it "broadcasts chat errors over ActionCable" do
      stream_chat = build_stream_chat(id: 456, parent_chat_id: 123, agent_name: "Mission Designer")
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_error_message(stream_chat, StandardError.new("boom"))

      expect(ActionCable.server).to have_received(:broadcast).with(
        stream_chat.ui_stream_channel_name,
        hash_including(
          type: "error",
          chat_id: 456,
          message: "boom",
          parent_chat_id: 123,
          agent_name: "Mission Designer",
        ),
      )
    end

    it "adds child chat metadata to chunk broadcasts when present" do
      stream_chat = build_stream_chat(id: 456, parent_chat_id: 123, agent_name: "Mission Designer")
      allow(ActionCable.server).to receive(:broadcast)

      job.broadcast_chunk(stream_chat, "pondering", kind: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        stream_chat.ui_stream_channel_name,
        hash_including(
          type: "chunk",
          chat_id: 456,
          parent_chat_id: 123,
          agent_name: "Mission Designer",
          content: "pondering",
          kind: "thinking",
        ),
      )
    end
  end

  describe "#append_stream_content" do
    it "returns early when the streamed content is blank" do
      transient_chat = Object.new

      expect { job.append_stream_content(transient_chat, "") }.not_to raise_error
    end

    it "accumulates streamed chunks until the stream ends" do
      message = build_persisted_message
      transient_chat = build_transient_chat(message)

      job.append_stream_content(transient_chat, "par")
      job.append_stream_content(transient_chat, "ti")
      job.append_stream_content(transient_chat, "al")
      job.persist_stream_content(transient_chat)

      expect(message.content).to eq("partial")
      expect(message.updates).to eq(1)
    end
  end

  describe "#persist_stream_content" do
    it "returns early when the in-flight assistant message is not persisted" do
      message = instance_double(Message, persisted?: false)
      transient_chat = build_transient_chat(message)

      allow(message).to receive(:update!)

      job.append_stream_content(transient_chat, "partial")

      expect { job.persist_stream_content(transient_chat) }.not_to raise_error
      expect(message).not_to have_received(:update!)
    end

    it "returns early when no streamed content has been accumulated" do
      message = build_persisted_message
      transient_chat = build_transient_chat(message)

      expect { job.persist_stream_content(transient_chat) }.not_to raise_error
      expect(message.updates).to eq(0)
    end

    it "does not rewrite a message whose final content already matches" do
      message = build_persisted_message(content: "partial")
      transient_chat = build_transient_chat(message)

      job.append_stream_content(transient_chat, "partial")
      job.persist_stream_content(transient_chat)

      expect(message.updates).to eq(0)
    end
  end

  describe "#missing_stream_content" do
    it "returns the full response content when nothing has streamed yet" do
      transient_chat = build_transient_chat(build_persisted_message)

      expect(job.send(:missing_stream_content, transient_chat, "complete")).to eq("complete")
    end

    it "returns an empty string when the streamed content already matches the final response" do
      transient_chat = build_transient_chat(build_persisted_message)
      job.append_stream_content(transient_chat, "complete")

      expect(job.send(:missing_stream_content, transient_chat, "complete")).to eq("")
    end

    it "returns only the missing suffix when the final response extends streamed content" do
      transient_chat = build_transient_chat(build_persisted_message)
      job.append_stream_content(transient_chat, "partial")

      expect(job.send(:missing_stream_content, transient_chat, "partial result")).to eq(" result")
    end
  end

  describe "#finalize_chat" do
    it "skips fallback title generation when a capability handled completion" do
      allow(Capabilities::EventDispatcher).to receive(:dispatch).and_return(true)

      expect { job.finalize_chat(chat) }.not_to raise_error

      expect(chat).to have_received(:idle!)
      expect(chat).to have_received(:broadcast_status_update)
    end

    it "preserves the cancelled state without running completion side effects" do
      allow(chat).to receive(:cancelled?).and_return(true)
      allow(Capabilities::EventDispatcher).to receive(:dispatch)

      expect { job.finalize_chat(chat) }.not_to raise_error

      expect(chat).not_to have_received(:idle!)
      expect(chat).to have_received(:broadcast_status_update)
      expect(Capabilities::EventDispatcher).not_to have_received(:dispatch)
    end
  end

  describe "#stream_phase_for" do
    it "returns nil when the chunk is a tool call" do
      chunk = Class.new do
        def tool_call? = true

        def content = nil

        def thinking = nil
      end.new

      expect(job.stream_phase_for(chunk)).to be_nil
    end

    it "returns thinking when the chunk exposes thinking content" do
      chunk = Class.new do
        attr_reader :thinking

        def initialize
          @thinking = "pondering"
        end

        def tool_call? = false

        def content = nil
      end.new

      expect(job.stream_phase_for(chunk)).to eq(:thinking)
    end

    it "returns nil when the chunk already has visible content" do
      chunk = Class.new do
        def tool_call? = false

        def content = "done"

        def thinking = nil
      end.new

      expect(job.stream_phase_for(chunk)).to be_nil
    end
  end

  describe "#advance_stream_phase" do
    it "broadcasts a status update when the phase changes" do
      chunk = Class.new do
        def tool_call? = false

        def content = nil

        def thinking = "pondering"
      end.new

      expect(job.advance_stream_phase(chat, nil, chunk)).to eq(:thinking)
      expect(chat).to have_received(:broadcast_status_update).with(phase: :thinking)
    end
  end
end
