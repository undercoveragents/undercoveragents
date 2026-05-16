# frozen_string_literal: true

# RubyLLM tool that delegates a question to a sub-agent.
#
# Each enabled sub-agent attached to a parent agent produces its own
# SubagentTool instance so the parent LLM can decide which sub-agent
# to invoke based on the tool name and description.
#
# Usage:
#   subagent = Agent.enabled.find(id)
#   tool = SubagentTool.for_agent(subagent)
#   chat.with_tool(tool)
#   chat.ask("Summarise last month's sales")
#
class SubagentTool < RubyLLM::Tool
  include SubagentToolChildResult
  include SubagentToolInputValues
  include SubagentToolStreaming

  DEFAULT_TOOL_SUMMARY = "Delegate a question to this sub-agent."
  DELEGATION_GUIDANCE = "Pass the user's request verbatim. Do not list resources or inspect the environment first,
  unless explicitly instructed. The sub-agent has full access and will handle discovery itself."
  DEFAULT_TOOL_PROMPT = [DEFAULT_TOOL_SUMMARY, DELEGATION_GUIDANCE].join(" ")
  CHILD_RESULT_TAG = "child_result"
  TOOL_MESSAGE_ROLES = ["assistant", "tool"].freeze

  param :question, desc: "The natural language question to send to the sub-agent"

  def self.for_agent(agent, parent_chat: nil, runtime_context: {})
    raise ArgumentError, "Expected an Agent" unless agent.is_a?(Agent)

    new(agent, parent_chat:, runtime_context:)
  end

  def initialize(agent, parent_chat: nil, runtime_context: {})
    super()
    @agent = agent
    @parent_chat = parent_chat
    @runtime_context = runtime_context.to_h.deep_symbolize_keys
  end

  def name
    base = @agent.name
                 .unicode_normalize(:nfkd)
                 .encode("ASCII", replace: "")
                 .gsub(/[^a-zA-Z0-9_-]/, "_").squeeze("_")
                 .gsub(/\A_|_\z/, "")
                 .downcase

    "ask_agent_#{base}"
  end

  def description
    [@agent.description.presence || DEFAULT_TOOL_SUMMARY, DELEGATION_GUIDANCE].join(" ")
  end

  def execute(question:)
    return stream_nested_subagent_response(question) if stream_nested_subagent_response?

    response = @agent.ask(question, **ask_options_for(question))
    response_content(response)
  rescue Chat::CancelledError
    raise
  rescue StandardError => e
    Rails.logger.error "[SubagentTool] Call failed for agent '#{@agent.name}': #{e.message}"
    "I couldn't get an answer from the sub-agent. Error: #{e.message}"
  end

  private

  def ask_options_for(_question)
    options = { parent_chat: @parent_chat }
    options[:runtime_context] = @runtime_context if @runtime_context.present?
    input_values = derived_input_values
    options[:input_values] = input_values if input_values.present?

    return options unless @agent.llm_config_source == "runtime"

    add_inherited_runtime_llm_options(options)
  end

  def add_inherited_runtime_llm_options(options)
    model_id = inherited_model_id
    llm_context = inherited_llm_context

    options[:model_id] = model_id if model_id.present?
    options[:llm_context] = llm_context if llm_context.present?
    options
  end

  def response_content(response)
    response.respond_to?(:content) ? response.content.to_s : response.to_s
  end
end
