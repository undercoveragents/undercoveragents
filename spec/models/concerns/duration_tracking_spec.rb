# frozen_string_literal: true

require "rails_helper"

RSpec.describe DurationTracking do
  let(:chat) { create(:chat, :with_agent) }
  let(:callbacks) { {} }

  before do
    # Capture the callbacks that setup_duration_tracking will register
    allow(chat).to receive(:before_message) { |&block| callbacks[:before_message] = block; chat } # rubocop:disable Style/Semicolon
    allow(chat).to receive(:after_message) { |&block| callbacks[:after_message] = block; chat } # rubocop:disable Style/Semicolon
    allow(chat).to receive(:before_tool_call) { |&block| callbacks[:before_tool_call] = block; chat } # rubocop:disable Style/Semicolon
    allow(chat).to receive(:after_tool_result) { |&block| callbacks[:after_tool_result] = block; chat } # rubocop:disable Style/Semicolon

    # Trigger the setup (normally called lazily from #ask)
    chat.send(:setup_message_duration_callbacks)
    chat.send(:setup_tool_call_duration_callbacks)
  end

  describe "message duration tracking" do
    it "records message duration_ms when end_message fires" do
      message = create(:message, chat:, role: :assistant, content: "test")

      callbacks[:before_message].call
      callbacks[:after_message].call(nil)

      expect(message.reload.duration_ms).to be_a(Integer)
      expect(message.reload.duration_ms).to be >= 0
    end

    it "resets timing state after recording duration" do
      create(:message, chat:, role: :assistant, content: "first")

      callbacks[:before_message].call
      callbacks[:after_message].call(nil)

      second = create(:message, chat:, role: :assistant, content: "second")
      callbacks[:after_message].call(nil)

      expect(second.reload.duration_ms).to be_nil
    end

    it "handles end_message gracefully when chat has no messages" do
      callbacks[:before_message].call
      expect { callbacks[:after_message].call(nil) }.not_to raise_error
    end

    it "prefers complete_start time over new_message time" do
      message = create(:message, chat:, role: :assistant, content: "test")

      # Simulate: complete sets start time, then new_message fires later (non-streaming)
      chat.instance_variable_set(:@_duration_complete_start, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 2.0)
      callbacks[:before_message].call # fires after LLM response in non-streaming
      callbacks[:after_message].call(nil)

      # Duration should be ~2000ms (from complete_start), not ~0ms (from new_message)
      expect(message.reload.duration_ms).to be >= 1900
    end

    it "falls back to new_message time when complete_start is cleared (tool-call loop)" do
      message = create(:message, chat:, role: :assistant, content: "test")

      # Simulate: complete_start was already consumed by a previous end_message
      chat.instance_variable_set(:@_duration_complete_start, nil)
      callbacks[:before_message].call
      sleep 0.01
      callbacks[:after_message].call(nil)

      expect(message.reload.duration_ms).to be >= 10
    end
  end

  describe "tool call duration tracking" do
    it "records tool call duration_ms when tool_result fires" do
      message = create(:message, chat:, role: :assistant, content: "test")
      tc = create(:tool_call, message:, tool_call_id: "call_abc")

      callbacks[:before_tool_call].call(double(id: "call_abc", name: "sql_query"))
      callbacks[:after_tool_result].call("query result")

      expect(tc.reload.duration_ms).to be_a(Integer)
      expect(tc.reload.duration_ms).to be >= 0
    end

    it "resets tool call state after recording duration" do
      message = create(:message, chat:, role: :assistant, content: "test")
      tc = create(:tool_call, message:, tool_call_id: "call_xyz")

      callbacks[:before_tool_call].call(double(id: "call_xyz", name: "sql_query"))
      callbacks[:after_tool_result].call("result")

      expect(tc.reload.duration_ms).to be >= 0

      # Subsequent tool_result without tool_call should not update anything
      tc2 = create(:tool_call, message:, tool_call_id: "call_zzz")
      callbacks[:after_tool_result].call("another result")
      expect(tc2.reload.duration_ms).to be_nil
    end

    it "handles missing tool call gracefully" do
      callbacks[:before_tool_call].call(double(id: "nonexistent_call", name: "sql_query"))
      expect { callbacks[:after_tool_result].call("result") }.not_to raise_error
    end
  end

  describe "tool call observers" do
    it "invokes before_tool_call_execution observers when tool_call fires" do
      observed = []
      chat.before_tool_call_execution { |tc| observed << tc.id }

      # Re-capture callbacks after registering observer
      allow(chat).to receive(:before_tool_call) { |&block| callbacks[:before_tool_call] = block; chat } # rubocop:disable Style/Semicolon
      allow(chat).to receive(:after_tool_result) { |&block| callbacks[:after_tool_result] = block; chat } # rubocop:disable Style/Semicolon
      chat.send(:setup_tool_call_duration_callbacks)

      callbacks[:before_tool_call].call(double(id: "call_obs", name: "sql_query"))

      expect(observed).to eq(["call_obs"])
    end

    it "invokes after_tool_call_execution observers when tool_result fires" do
      message = create(:message, chat:, role: :assistant, content: "test")
      create(:tool_call, message:, tool_call_id: "call_obs2")

      observed = []
      chat.after_tool_call_execution { |tc_id, tc_name, dur| observed << [tc_id, tc_name, dur] }

      # Re-capture callbacks after registering observer
      allow(chat).to receive(:before_tool_call) { |&block| callbacks[:before_tool_call] = block; chat } # rubocop:disable Style/Semicolon
      allow(chat).to receive(:after_tool_result) { |&block| callbacks[:after_tool_result] = block; chat } # rubocop:disable Style/Semicolon
      chat.send(:setup_tool_call_duration_callbacks)

      callbacks[:before_tool_call].call(double(id: "call_obs2", name: "my_tool"))
      callbacks[:after_tool_result].call("result")

      expect(observed.size).to eq(1)
      expect(observed.first[0]).to eq("call_obs2")
      expect(observed.first[1]).to eq("my_tool")
      expect(observed.first[2]).to be_a(Integer)
    end

    it "supports multiple observers" do
      results_a = []
      results_b = []
      chat.before_tool_call_execution { |tc| results_a << tc.name }
      chat.before_tool_call_execution { |tc| results_b << tc.name }

      # Re-capture callbacks after registering observers
      allow(chat).to receive(:before_tool_call) { |&block| callbacks[:before_tool_call] = block; chat } # rubocop:disable Style/Semicolon
      allow(chat).to receive(:after_tool_result) { |&block| callbacks[:after_tool_result] = block; chat } # rubocop:disable Style/Semicolon
      chat.send(:setup_tool_call_duration_callbacks)

      callbacks[:before_tool_call].call(double(id: "call_multi", name: "sql_query"))

      expect(results_a).to eq(["sql_query"])
      expect(results_b).to eq(["sql_query"])
    end
  end

  describe "lazy initialization via #ask" do
    it "sets up tracking on first ask call" do
      fresh_chat = create(:chat, :with_agent)
      expect(fresh_chat.instance_variable_get(:@duration_tracking_initialized)).to be_nil

      # Stub ask's super to prevent actual LLM call
      allow(fresh_chat).to receive_messages(before_message: fresh_chat, after_message: fresh_chat,
                                            before_tool_call: fresh_chat, after_tool_result: fresh_chat,)
      allow(fresh_chat).to receive(:create_user_message)
      allow(fresh_chat).to receive(:complete)

      fresh_chat.ask("hello")

      expect(fresh_chat.instance_variable_get(:@duration_tracking_initialized)).to be(true)
    end

    it "skips setup on subsequent ask calls when already initialized" do
      fresh_chat = create(:chat, :with_agent)

      allow(fresh_chat).to receive_messages(before_message: fresh_chat, after_message: fresh_chat,
                                            before_tool_call: fresh_chat, after_tool_result: fresh_chat,)
      allow(fresh_chat).to receive(:create_user_message)
      allow(fresh_chat).to receive(:complete)

      # First call initializes tracking
      fresh_chat.ask("hello")
      expect(fresh_chat.instance_variable_get(:@duration_tracking_initialized)).to be(true)

      # Second call should skip setup — covers the `unless @duration_tracking_initialized` else branch
      allow(fresh_chat).to receive(:setup_duration_tracking)
      fresh_chat.ask("world")
      expect(fresh_chat).not_to have_received(:setup_duration_tracking)
    end
  end

  describe "#complete override" do
    it "records start time before delegating to super" do
      fresh_chat = create(:chat, :with_agent)

      # Stub super's complete to avoid real LLM calls
      allow(fresh_chat).to receive(:to_llm).and_return(double(complete: nil))

      fresh_chat.complete

      expect(fresh_chat.instance_variable_get(:@_duration_complete_start)).to be_a(Float)
      expect(fresh_chat.instance_variable_get(:@_duration_complete_start)).to be_positive
    end
  end
end
