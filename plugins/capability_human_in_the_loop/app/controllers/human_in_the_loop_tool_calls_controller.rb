# frozen_string_literal: true

class HumanInTheLoopToolCallsController < ApplicationController
  before_action :set_tool_call
  before_action :authorize_tool_call!

  def submit
    state = @tool_call.human_in_the_loop_tool_call_state
    return render_widget(state:) if state.answered?

    result = Capabilities::HumanInTheLoop::ResponseProcessor.new(state, response_params).call

    if result.success?
      resume_chat!(previous_state: state, submitted_state: result.state)
      render_widget(state: @tool_call.human_in_the_loop_tool_call_state, responses: result.responses)
    else
      render_widget(state:, responses: result.responses, errors: result.errors, status: :unprocessable_content)
    end
  rescue StandardError => e
    Rails.logger.error "[HumanInTheLoopToolCallsController] Submit failed: #{e.message}"
    render_widget(
      state: @tool_call.human_in_the_loop_tool_call_state,
      errors: { base: "Could not submit your answers. Please try again." },
      status: :unprocessable_content,
    )
  end

  private

  def resume_chat!(previous_state:, submitted_state:)
    @tool_call.update!(arguments: submitted_state.to_h)
    @tool_call.reload
    Capabilities::HumanInTheLoop::ChatResumeService.new(@tool_call).call
  rescue StandardError
    restore_previous_state!(previous_state)
    raise
  end

  def restore_previous_state!(state)
    @tool_call.update!(arguments: state.to_h)
    @tool_call.reload
  end

  def set_tool_call
    @tool_call = ToolCall.find(params.expect(:id))
  end

  def authorize_tool_call!
    return head(:not_found) unless tool_call_accessible?

    nil
  end

  def render_widget(state:, responses: nil, errors: {}, status: :ok)
    render(
      partial: "human_in_the_loop_tool_calls/tool_call_widget",
      locals: {
        tool_call: @tool_call,
        state:,
        responses: responses || state.answers,
        errors: errors.with_indifferent_access,
      },
      status:,
    )
  end

  def response_params
    raw = params[:responses]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end

  def hittl_tool_call?
    @tool_call.respond_to?(:human_in_the_loop_tool_call?) && @tool_call.human_in_the_loop_tool_call?
  end

  def tool_call_accessible?
    current_user.present? && hittl_tool_call? && @tool_call.message&.chat&.user_id == current_user.id
  end
end
