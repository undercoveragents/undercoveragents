# frozen_string_literal: true

module Missions
  module Nodes
    # Node: Agent — invokes a configured Agent by ID.
    class Agent
      include MissionNodePlugin

      class << self
        def node_type = "agent"
        def node_label = "Agent"
        def node_icon = "fa-solid fa-user-secret"
        def node_color = "#4f46e5"
        def node_category = :llm
        def node_description = "Invokes an AI agent"

        def field_contracts
          [
            field_contract(
              key: "prompt",
              kind: :template,
              value_type: :string,
              description: "Prompt template with {{variable}} interpolation",
            ),
            field_contract(
              key: "agent_id",
              kind: :id_ref,
              value_type: :string,
              description: "Agent to invoke",
              required: true,
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "response", type: :string, description: "Text returned by the agent" },
            ],
          )
        end

        def default_output_ports
          [{ key: "default", label: "Response" }]
        end

        def designer_instructions
          <<~INSTRUCTIONS.strip
            ## Agent (type: "agent")
            Invokes a pre-configured AI agent by ID.

            ### Configuration
            ```json
            {
              "agent_id": "5",
              "prompt": "Analyze this data: {{summarizer.response}}"
            }
            ```
            - `agent_id` (required): ID of the agent to invoke. Use `list_resources(kind: "agents")` to see available agents.
            - `prompt`: Prompt template with {{variable}} interpolation. If omitted, the node uses the current branch input.

            Agents have their own tools, instructions, and LLM configuration.
            They are more powerful than plain LLM nodes when you need tool usage.

            ### Output Ports
            - `default`: Response

            ### Output Variables
            - `response` (string): Text returned by the agent
          INSTRUCTIONS
        end
      end

      register_node!

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        agent = resolve_agent(node_data["agent_id"])
        return agent unless agent.is_a?(::Agent)

        prompt = resolve_prompt(context, node_data)
        if prompt.blank?
          return NodeResult.new(status: :failure, output: "Agent node has no prompt and no input — nothing to send")
        end

        response = invoke_agent(agent, node_data, prompt)
        return empty_agent_response if response.nil? || response.content.nil?

        NodeResult.new(status: :success, output: response.content, variables: { "response" => response.content })
      rescue StandardError => e
        NodeResult.new(status: :failure, output: "Agent error: #{e.message}")
      end

      private

      def resolve_agent(agent_id)
        return NodeResult.new(status: :failure, output: "Agent not configured") if agent_id.blank?

        ::Agent.find_by(id: agent_id) || NodeResult.new(status: :failure, output: "Agent not found (id: #{agent_id})")
      end

      def empty_agent_response
        NodeResult.new(status: :failure, output: "Agent returned an empty response")
      end

      def resolve_prompt(context, node_data)
        prompt_template = node_data["prompt"] || node_data["description"] || ""
        prompt = context.interpolate(prompt_template)
        prompt.presence || context.current_input.to_s.presence
      end

      def invoke_agent(agent, _node_data, prompt)
        agent.ask(prompt)
      end
    end
  end
end
