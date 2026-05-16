# frozen_string_literal: true

module AgentDesigner
  class DebugAgentTool < RubyLLM::Tool
    include AgentLookup
    include PolicyAuthorizable

    description "Send a synchronous debug prompt to an agent, persist the resulting chat, " \
                "and return the answer plus the created chat ID."

    param :prompt,
          desc: "The exact debug prompt to send to the agent."

    param :agent_id,
          desc: "Optional numeric ID or slug. Omit to debug the current agent from page context.",
          required: false

    param :input_values,
          desc: "Optional JSON object for the agent input variables.",
          required: false

    param :detail,
          desc: "Response detail for the created chat: 'summary' (default) or 'full'.",
          required: false

    param :message_limit,
          desc: "Optional number of most recent messages to include from the created chat.",
          required: false

    def initialize(runtime_context:, current_agent: nil)
      super()
      @runtime_context = runtime_context
      @current_agent = current_agent
    end

    def name = "debug_agent"

    def execute(prompt:, agent_id: nil, input_values: nil, detail: nil, message_limit: nil)
      agent = authorized_agent(agent_id)
      return missing_agent_message if agent.nil?

      question = normalized_prompt(prompt)
      chat = build_debug_chat(agent, input_values)
      response = chat.ask(question)

      success_message(agent, chat, response, detail:, message_limit:)
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error debugging agent: #{e.message}"
    end

    private

    def authorized_agent(agent_id)
      agent = resolve_agent(agent_id)
      return if agent.nil?

      authorize_policy!(agent, :show?, user: @runtime_context.user)
      agent
    end

    def build_debug_chat(agent, input_values)
      agent.build_chat(
        parent_chat: @runtime_context.chat,
        execution_context: :system,
        user: @runtime_context.user,
        title: "Agent debug: #{agent.name}",
        input_values: parse_json_object(input_values, field_name: "input_values"),
        runtime_context: @runtime_context.to_h,
      )
    end

    def normalized_prompt(prompt)
      question = prompt.to_s.strip
      raise ArgumentError, "prompt is required." if question.blank?

      question
    end

    def success_message(agent, chat, response, detail:, message_limit:)
      [
        "Agent debug chat completed.",
        "- Agent: #{agent.name} (`#{agent.id}`)",
        "- Chat ID: `#{chat.id}`",
        "- Response preview: #{preview(response)}",
        "",
        formatter(agent).format_chat(chat, detail:, message_limit:),
      ].join("\n")
    end

    def formatter(agent)
      AgentDesigner::ChatDebugFormatter.new(agent:)
    end

    def parse_json_object(raw, field_name:)
      return {} if raw.blank?

      parsed = case raw
               when ActionController::Parameters then raw.to_unsafe_h
               when Hash then raw
               else JSON.parse(raw)
               end
      raise ArgumentError, "#{field_name} must be a JSON object." unless parsed.is_a?(Hash)

      parsed.stringify_keys
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid JSON for #{field_name}: #{e.message}"
    end

    def preview(response)
      text = response.to_s.gsub(/\s+/, " ").strip

      return "None." if text.blank?
      return text if text.length <= 180

      "#{text[0, 165]}..."
    end
  end
end
