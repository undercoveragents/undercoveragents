# frozen_string_literal: true

# Automatic duration tracking for messages and tool calls.
#
# When included in the Chat model (which uses RubyLLM's acts_as_chat),
# this concern registers lifecycle callbacks to measure wall-clock time
# for every LLM message round-trip and tool call execution.
#
# Chat wires this concern into +ask+ and +complete+ so it works for **every**
# chat, including sub-agent chats that are not created through the playground
# job. The callbacks are set up lazily on the first +ask+ call because
# RubyLLM's callback registration requires the model to be configured.
#
# == Non-streaming fix
#
# RubyLLM fires +before_message+ AFTER the LLM response in non-streaming mode,
# so the time between +before_message+ and +after_message+ would be just a few ms.
# We record the start time in +complete+ (before the LLM call) and use it as the
# primary timing source in +after_message+.
module DurationTracking
  extend ActiveSupport::Concern

  # Registers a callback invoked when a tool call begins execution.
  # The block receives the RubyLLM tool_call object (responds to #id, #name, #arguments).
  def before_tool_call_execution(&block)
    @_before_tool_call_execution_observers ||= []
    @_before_tool_call_execution_observers << block
  end

  # Registers a callback invoked when a tool call finishes execution.
  # The block receives (tool_call_id, tool_name, duration_ms).
  def after_tool_call_execution(&block)
    @_after_tool_call_execution_observers ||= []
    @_after_tool_call_execution_observers << block
  end

  private

  def setup_duration_tracking
    @duration_tracking_initialized = true
    setup_message_duration_callbacks
    setup_tool_call_duration_callbacks
  end

  def setup_message_duration_callbacks
    before_message do
      # For streaming: fires before LLM starts → accurate.
      # For non-streaming: fires after LLM response → we use @_duration_complete_start instead.
      @_duration_message_start = duration_monotonic_now
    end

    after_message do |_msg|
      # Prefer @_duration_complete_start (set before LLM call) for accurate non-streaming timing.
      # Fall back to @_duration_message_start for tool-call-loop messages where complete_start was cleared.
      start_time = @_duration_complete_start || @_duration_message_start
      next unless start_time

      duration = duration_ms_since(start_time)
      messages.order(:id).last&.update_column(:duration_ms, duration) # rubocop:disable Rails/SkipsModelValidations
      @_duration_complete_start = nil
      @_duration_message_start = nil
    end
  end

  def setup_tool_call_duration_callbacks
    before_tool_call do |tool_call|
      @_tracking_tool_id = tool_call.id
      @_tracking_tool_name = tool_call.name
      @_tracking_tool_start = duration_monotonic_now
      ToolCall.find_by(tool_call_id: tool_call.id)&.sync_display_metadata!
      @_before_tool_call_execution_observers&.each { |cb| cb.call(tool_call) }
    end

    after_tool_result { |_result| finalize_tool_call_tracking }
  end

  def finalize_tool_call_tracking
    return unless @_tracking_tool_start && @_tracking_tool_id

    duration = duration_ms_since(@_tracking_tool_start)
    tool_call_record = ToolCall.find_by(tool_call_id: @_tracking_tool_id)
    tool_call_record&.sync_display_metadata!
    tool_call_record&.update_column(:duration_ms, duration) # rubocop:disable Rails/SkipsModelValidations
    @_after_tool_call_execution_observers&.each { |cb| cb.call(@_tracking_tool_id, @_tracking_tool_name, duration) }
    @_tracking_tool_start = nil
    @_tracking_tool_id = nil
    @_tracking_tool_name = nil
  end

  def duration_monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def duration_ms_since(start)
    ((duration_monotonic_now - start) * 1000).round
  end
end
