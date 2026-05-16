# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubagentTool do
  let(:subagent) do
    build(:agent, name: "Research Assistant", description: "Helps with research questions", model_id: "gpt-4.1")
  end
  let(:mission_input_schema) do
    [
      { "variable_name" => "mission_name", "label" => "Mission Name", "field_type" => "string" },
      { "variable_name" => "mission_description", "label" => "Mission Description", "field_type" => "string" },
    ]
  end
  let(:agent_input_schema) do
    [
      { "variable_name" => "agent_name", "label" => "Agent Name", "field_type" => "string" },
      { "variable_name" => "agent_description", "label" => "Agent Description", "field_type" => "string" },
    ]
  end
  let(:tool_input_schema) do
    [
      { "variable_name" => "tool_name", "label" => "Tool Name", "field_type" => "string" },
      { "variable_name" => "tool_description", "label" => "Tool Description", "field_type" => "string" },
      { "variable_name" => "tool_type", "label" => "Tool Type", "field_type" => "string" },
      { "variable_name" => "tool_type_label", "label" => "Tool Type Label", "field_type" => "string" },
    ]
  end
  let(:channel_input_schema) do
    [
      { "variable_name" => "channel_name", "label" => "Channel Name", "field_type" => "string" },
      { "variable_name" => "channel_type", "label" => "Channel Type", "field_type" => "string" },
      { "variable_name" => "channel_title", "label" => "Channel Title", "field_type" => "string" },
    ]
  end
  let(:client_input_schema) do
    [
      { "variable_name" => "client_name", "label" => "Client Name", "field_type" => "string" },
      { "variable_name" => "client_title", "label" => "Client Title", "field_type" => "string" },
    ]
  end
  let(:skill_catalog_input_schema) do
    [
      { "variable_name" => "skill_catalog_name", "label" => "Skill Catalog Name", "field_type" => "string" },
      {
        "variable_name" => "skill_catalog_description",
        "label" => "Skill Catalog Description",
        "field_type" => "string",
      },
    ]
  end

  def current_agent_input_values
    {
      agent_name: "Operations Agent",
      agent_description: "Handles operations",
    }
  end

  def current_channel_input_values
    {
      channel_name: "Support Portal",
      channel_type: "client",
      channel_title: "<p>Support Portal</p>",
    }
  end

  def current_tool_input_values
    {
      tool_name: "Orders Explorer",
      tool_description: "Reads the order catalog",
      tool_type: "sql_query",
      tool_type_label: "SQL Query",
    }
  end

  def current_skill_catalog_input_values
    {
      skill_catalog_name: "Operations Skills",
      skill_catalog_description: "Knowledge for the operations team",
    }
  end

  def current_test_suite_input_values
    {
      test_suite_name: "Regression Suite",
      test_suite_description: "Checks the main support flow",
      test_suite_type: "agent",
    }
  end

  def test_suite_input_schema
    [
      { "variable_name" => "test_suite_name", "label" => "Test Suite Name", "field_type" => "string" },
      {
        "variable_name" => "test_suite_description",
        "label" => "Test Suite Description",
        "field_type" => "string",
      },
      { "variable_name" => "test_suite_type", "label" => "Test Suite Type", "field_type" => "string" },
    ]
  end

  describe ".for_agent" do
    it "creates a tool instance for a valid agent" do
      tool = described_class.for_agent(subagent)

      expect(tool).to be_a(described_class)
    end

    it "raises ArgumentError for non-Agent objects" do
      expect { described_class.for_agent("not an agent") }
        .to raise_error(ArgumentError, "Expected an Agent")
    end
  end

  describe "#name" do
    it "generates a unique tool name from the agent name" do
      tool = described_class.for_agent(subagent)

      expect(tool.name).to eq("ask_agent_research_assistant")
    end

    it "sanitises special characters" do
      subagent.name = "My Agent (v2.0)!"
      tool = described_class.for_agent(subagent)

      expect(tool.name).to match(/\Aask_agent_[a-z0-9_-]+\z/)
    end
  end

  describe "#description" do
    it "keeps the agent description and appends delegation guidance", :aggregate_failures do
      tool = described_class.for_agent(subagent)

      expect(tool.description).to start_with("Helps with research questions")
      expect(tool.description).to include("Pass the user's request verbatim")
      expect(tool.description).to include("Do not list resources or inspect the environment first")
    end

    it "does not override the agent description for mission designer agents", :aggregate_failures do
      subagent.agent_type = "mission_designer"
      subagent.description = "Mission authoring specialist"
      tool = described_class.for_agent(subagent)

      expect(tool.description).to start_with("Mission authoring specialist")
      expect(tool.description).to include("Pass the user's request verbatim")
    end

    it "falls back to default when description is blank" do
      subagent.description = ""
      tool = described_class.for_agent(subagent)

      expect(tool.description).to eq(described_class::DEFAULT_TOOL_PROMPT)
    end
  end

  describe "#execute" do
    def stub_streaming_child_chat(child_chat, callbacks, child_agent_name)
      allow(child_chat).to receive(:before_tool_call_execution) { |&block| callbacks[:start] = block }
      allow(child_chat).to receive(:after_tool_call_execution) { |&block| callbacks[:complete] = block }
      allow(child_chat).to receive(:streaming!)
      allow(child_chat).to receive(:idle!)
      allow(child_chat).to receive(:broadcast_status_update)
      allow(child_chat).to receive(:ui_stream_payload) do |payload|
        payload.merge(parent_chat_id: 123, agent_name: child_agent_name)
      end
    end

    def build_streaming_chunks
      thinking = Struct.new(:text).new("Planning the mission update")
      thinking_chunk = instance_double(RubyLLM::Chunk, thinking:, content: nil, tool_call?: false)
      content_chunk = instance_double(RubyLLM::Chunk, thinking: nil, content: "Done", tool_call?: false)

      [thinking_chunk, content_chunk]
    end

    def stub_streaming_metadata(metadata)
      allow(ToolCalls::DisplayMetadataResolver).to receive(:resolve).and_return(metadata)
      allow(metadata).to receive(:sample_phrase).with(status: :running).and_return("Reading the mission flow")
      allow(metadata).to receive(:sample_phrase).with(status: :complete).and_return("Mission read complete")
      allow(metadata).to receive(:widget_payload)
        .with(status: :running, phrase: "Reading the mission flow")
        .and_return({})
      allow(metadata).to receive(:widget_payload)
        .with(status: :complete, phrase: "Mission read complete")
        .and_return({})
    end

    def expect_child_chat_stream_lifecycle(child_chat)
      expect(child_chat).to have_received(:streaming!)
      expect(child_chat).to have_received(:broadcast_status_update).with(phase: nil).at_least(:once)
      expect(child_chat).to have_received(:broadcast_status_update).with(phase: :thinking)
      expect(child_chat).to have_received(:idle!)
    end

    def expect_child_chat_chunk_broadcast(child_chat, agent_name)
      expect(ActionCable.server).to have_received(:broadcast).with(
        child_chat.ui_stream_channel_name,
        hash_including(
          type: "chunk",
          chat_id: 456,
          content: "Planning the mission update",
          kind: "thinking",
          agent_name:,
        ),
      )
    end

    def expect_child_chat_tool_event_broadcast(child_chat)
      expect(ActionCable.server).to have_received(:broadcast).with(
        child_chat.ui_stream_channel_name,
        hash_including(
          type: "tool_event",
          chat_id: 456,
          event: "start",
          tool_call_id: "call-1",
          tool_name: "read_mission_flow",
          display_name: "Read mission flow",
        ),
      )
    end

    def expect_agent_designer_call(agent_designer, current_agent, input_values)
      runtime_context = { current_agent: }

      allow(agent_designer).to receive(:ask)
        .with(
          "tune this assistant",
          parent_chat: nil,
          runtime_context:,
          input_values:,
        ).and_return("done")

      runtime_context
    end

    def expect_tool_designer_call(tool_designer, current_tool, input_values)
      runtime_context = { current_tool: }

      allow(tool_designer).to receive(:ask)
        .with(
          "tune this tool",
          parent_chat: nil,
          runtime_context:,
          input_values:,
        ).and_return("done")

      runtime_context
    end

    def expect_channel_designer_call(channel_designer, current_channel, input_values)
      runtime_context = { current_channel: }

      allow(channel_designer).to receive(:ask)
        .with(
          "tune this channel",
          parent_chat: nil,
          runtime_context:,
          input_values:,
        ).and_return("done")

      runtime_context
    end

    def expect_skill_catalog_designer_call(skill_catalog_designer, current_skill_catalog, input_values)
      runtime_context = { current_skill_catalog: }

      allow(skill_catalog_designer).to receive(:ask)
        .with(
          "tune this catalog",
          parent_chat: nil,
          runtime_context:,
          input_values:,
        ).and_return("done")

      runtime_context
    end

    def expect_test_suite_designer_call(test_suite_designer, current_test_suite, input_values)
      runtime_context = { current_test_suite: }

      allow(test_suite_designer).to receive(:ask)
        .with(
          "tune this suite",
          parent_chat: nil,
          runtime_context:,
          input_values:,
        ).and_return("done")

      runtime_context
    end

    def build_current_channel
      build_stubbed(
        :channel,
        :client,
        name: "Support Portal",
        configuration: { "title" => "<p>Support Portal</p>" },
      )
    end

    def build_channel_designer(input_schema)
      build(
        :agent,
        name: "Channel Designer",
        builtin_key: "channel_designer",
        input_schema:,
      )
    end

    def build_current_tool
      build_stubbed(
        :tool,
        name: "Orders Explorer",
        description: "Reads the order catalog",
        tool_type: "sql_query",
      )
    end

    def build_tool_designer(tool_input_schema)
      build(
        :agent,
        name: "Tool Designer",
        builtin_key: "tool_designer",
        input_schema: tool_input_schema,
      )
    end

    def child_message(role, content)
      instance_double(Message, role:, content:)
    end

    def build_designer_child_chat(messages)
      instance_double(
        Chat,
        id: 456,
        ui_stream_channel_name: "chat_user_stream_456",
        messages:,
      )
    end

    def structured_designer_messages
      [
        child_message("tool", "Mission updated successfully.\n- ID: `42`\n- Name: Policy Mission"),
        child_message("tool", "## Warnings\n- Missing fallback path"),
        child_message("assistant", "Updated the mission."),
      ]
    end

    def extract_child_result_payload(result)
      JSON.parse(result.match(%r{<child_result>\n(?<payload>\{.*\})\n</child_result>}m)[:payload])
    end

    def prepare_designer_tool(parent_chat:, messages:, response_content:)
      mission_designer = build(:agent, name: "Mission Designer", builtin_key: "mission_designer")
      designer_tool = described_class.for_agent(mission_designer, parent_chat:)
      designer_child_chat = build_designer_child_chat(messages)
      designer_callbacks = {}

      allow(mission_designer).to receive(:build_chat).with(parent_chat:).and_return(designer_child_chat)
      stub_streaming_child_chat(designer_child_chat, designer_callbacks, mission_designer.name)
      allow(ActionCable.server).to receive(:broadcast)
      allow(designer_child_chat).to receive(:ask)
        .and_return(instance_double(RubyLLM::Message, content: response_content))

      designer_tool
    end

    def expect_mission_child_result_payload(payload)
      expect(payload).to include(
        "status" => "warning",
        "warnings" => ["Missing fallback path"],
        "blockers" => [],
      )
      expect(payload["record_ids"]).to include(
        hash_including(
          "resource" => "mission",
          "id" => "42",
          "label" => "Policy Mission",
          "action" => "updated",
        ),
      )
    end

    it "delegates the question to the subagent" do
      tool = described_class.for_agent(subagent)

      allow(subagent).to receive(:ask).with("What is 2+2?", parent_chat: nil).and_return("4")

      result = tool.execute(question: "What is 2+2?")

      expect(result).to eq("4")
      expect(subagent).to have_received(:ask).with("What is 2+2?", parent_chat: nil)
    end

    it "passes parent_chat to the subagent" do
      parent_chat = instance_double(Chat)
      tool = described_class.for_agent(subagent, parent_chat:)

      allow(subagent).to receive(:ask).with("test", parent_chat:).and_return("answer")

      result = tool.execute(question: "test")

      expect(result).to eq("answer")
      expect(subagent).to have_received(:ask).with("test", parent_chat:)
    end

    it "returns the content of RubyLLM message-like responses" do
      tool = described_class.for_agent(subagent)
      llm_response = instance_double(RubyLLM::Message, content: "4")

      allow(subagent).to receive(:ask).with("What is 2+2?", parent_chat: nil).and_return(llm_response)

      result = tool.execute(question: "What is 2+2?")

      expect(result).to eq("4")
    end

    it "passes runtime context through to the subagent" do
      mission = build_stubbed(:mission)
      tool = described_class.for_agent(subagent, runtime_context: { mission: })

      allow(subagent).to receive(:ask).with(
        "use the current mission",
        parent_chat: nil,
        runtime_context: { mission: },
      ).and_return("answer")

      expect(tool.execute(question: "use the current mission")).to eq("answer")
      expect(subagent).to have_received(:ask).with(
        "use the current mission",
        parent_chat: nil,
        runtime_context: { mission: },
      )
    end

    it "derives mission input values for mission-aware subagents" do
      mission = build_stubbed(:mission, name: "Policy Mission", description: "Main policy flow")
      input_values = {
        mission_name: "Policy Mission",
        mission_description: "Main policy flow",
      }
      mission_designer = build(
        :agent,
        name: "Mission Designer",
        builtin_key: "mission_designer",
        input_schema: mission_input_schema,
      )
      tool = described_class.for_agent(mission_designer, runtime_context: { mission: })

      allow(mission_designer).to receive(:ask)
        .with("set this up", parent_chat: nil, runtime_context: { mission: }, input_values:)
        .and_return("done")

      expect(tool.execute(question: "set this up")).to eq("done")
      expect(mission_designer).to have_received(:ask)
        .with("set this up", parent_chat: nil, runtime_context: { mission: }, input_values:)
    end

    it "skips derived mission input values for non-mission runtime context" do
      mission_designer = build(:agent, name: "Mission Designer", input_schema: mission_input_schema)
      tool = described_class.for_agent(mission_designer, runtime_context: { mission: Object.new })

      allow(mission_designer).to receive(:ask)
        .with("set this up", parent_chat: nil, runtime_context: { mission: kind_of(Object) })
        .and_return("done")

      expect(tool.execute(question: "set this up")).to eq("done")
      expect(mission_designer).to have_received(:ask)
        .with("set this up", parent_chat: nil, runtime_context: { mission: kind_of(Object) })
    end

    it "only passes mission_name when that is the only requested schema value" do
      mission = build_stubbed(:mission, name: "Policy Mission", description: "Main policy flow")
      mission_designer = build(:agent, name: "Mission Designer",
                                       input_schema: [mission_input_schema.first],)
      tool = described_class.for_agent(mission_designer, runtime_context: { mission: })

      allow(mission_designer).to receive(:ask)
        .with(
          "name only",
          parent_chat: nil,
          runtime_context: { mission: },
          input_values: { mission_name: "Policy Mission" },
        ).and_return("done")

      expect(tool.execute(question: "name only")).to eq("done")
    end

    it "only passes mission_description when that is the only requested schema value" do
      mission = build_stubbed(:mission, name: "Policy Mission", description: "Main policy flow")
      mission_designer = build(:agent, name: "Mission Designer",
                                       input_schema: [mission_input_schema.second],)
      tool = described_class.for_agent(mission_designer, runtime_context: { mission: })

      allow(mission_designer).to receive(:ask)
        .with(
          "description only",
          parent_chat: nil,
          runtime_context: { mission: },
          input_values: { mission_description: "Main policy flow" },
        ).and_return("done")

      expect(tool.execute(question: "description only")).to eq("done")
    end

    it "derives current agent input values for agent-aware subagents" do
      current_agent = build_stubbed(:agent, name: "Operations Agent", description: "Handles operations")
      agent_designer = build(
        :agent,
        name: "Agent Designer",
        builtin_key: "agent_designer",
        input_schema: agent_input_schema,
      )
      runtime_context = expect_agent_designer_call(agent_designer, current_agent, current_agent_input_values)
      tool = described_class.for_agent(agent_designer, runtime_context:)

      expect(tool.execute(question: "tune this assistant")).to eq("done")
      expect(agent_designer).to have_received(:ask)
        .with(
          "tune this assistant",
          parent_chat: nil,
          runtime_context:,
          input_values: current_agent_input_values,
        )
    end

    it "skips derived agent input values when the schema does not request them" do
      current_agent = build_stubbed(:agent, name: "Operations Agent", description: "Handles operations")
      agent_designer = build(
        :agent,
        name: "Agent Designer",
        builtin_key: "agent_designer",
        input_schema: [{ "variable_name" => "other_value", "label" => "Other", "field_type" => "string" }],
      )
      runtime_context = { current_agent: }
      tool = described_class.for_agent(agent_designer, runtime_context:)

      allow(agent_designer).to receive(:ask)
        .with("tune this assistant", parent_chat: nil, runtime_context:)
        .and_return("done")

      expect(tool.execute(question: "tune this assistant")).to eq("done")
    end

    it "derives current tool input values for tool-aware subagents" do
      current_tool = build_current_tool
      allow(current_tool).to receive(:type_label).and_return("SQL Query")
      tool_designer = build_tool_designer(tool_input_schema)
      runtime_context = expect_tool_designer_call(tool_designer, current_tool, current_tool_input_values)
      tool = described_class.for_agent(tool_designer, runtime_context:)

      expect(tool.execute(question: "tune this tool")).to eq("done")
      expect(tool_designer).to have_received(:ask)
        .with(
          "tune this tool",
          parent_chat: nil,
          runtime_context:,
          input_values: current_tool_input_values,
        )
    end

    it "skips derived tool input values when the schema does not request them" do
      current_tool = build_stubbed(
        :tool,
        name: "Orders Explorer",
        description: "Reads the order catalog",
        tool_type: "sql_query",
      )
      tool_designer = build(
        :agent,
        name: "Tool Designer",
        builtin_key: "tool_designer",
        input_schema: [{ "variable_name" => "other_value", "label" => "Other", "field_type" => "string" }],
      )
      runtime_context = { current_tool: }
      tool = described_class.for_agent(tool_designer, runtime_context:)

      allow(tool_designer).to receive(:ask)
        .with("tune this tool", parent_chat: nil, runtime_context:)
        .and_return("done")

      expect(tool.execute(question: "tune this tool")).to eq("done")
    end

    it "derives current channel input values for channel-aware subagents" do
      current_channel = build_current_channel
      channel_designer = build_channel_designer(channel_input_schema)
      runtime_context = expect_channel_designer_call(channel_designer, current_channel, current_channel_input_values)
      tool = described_class.for_agent(channel_designer, runtime_context:)

      expect(tool.execute(question: "tune this channel")).to eq("done")
      expect(channel_designer).to have_received(:ask)
        .with(
          "tune this channel",
          parent_chat: nil,
          runtime_context:,
          input_values: current_channel_input_values,
        )
    end

    it "ignores unavailable channel input values for channel-aware subagents" do
      current_channel = build_current_channel
      channel_designer = build_channel_designer(
        [{ "variable_name" => "other_value", "label" => "Other", "field_type" => "string" }],
      )
      runtime_context = { current_channel: }
      tool = described_class.for_agent(channel_designer, runtime_context:)

      allow(channel_designer).to receive(:ask)
        .with("tune this channel", parent_chat: nil, runtime_context:)
        .and_return("done")

      expect(tool.execute(question: "tune this channel")).to eq("done")
      expect(channel_designer).to have_received(:ask)
        .with(
          "tune this channel",
          parent_chat: nil,
          runtime_context:,
        )
    end

    it "inherits runtime model and context from the parent chat for runtime subagents" do
      runtime_subagent = build(:agent, name: "Code Assistant", llm_config_source: "runtime", model_id: nil)
      parent_model = Struct.new(:model_id).new("gpt-4.1")
      parent_agent = build(:agent, model_id: "gpt-4.1")
      llm_context = Object.new
      parent_chat = Struct.new(:model, :agent, :context).new(parent_model, parent_agent, llm_context)
      tool = described_class.for_agent(runtime_subagent, parent_chat:)

      allow(runtime_subagent).to receive(:ask).with(
        "write code",
        parent_chat:,
        model_id: "gpt-4.1",
        llm_context:,
      ).and_return("answer")

      expect(tool.execute(question: "write code")).to eq("answer")
      expect(runtime_subagent).to have_received(:ask).with(
        "write code",
        parent_chat:,
        model_id: "gpt-4.1",
        llm_context:,
      )
    end

    it "omits inherited runtime config when the parent chat does not provide it" do
      runtime_subagent = build(:agent, name: "Code Assistant", llm_config_source: "runtime", model_id: nil)
      parent_chat = Struct.new(:model, :agent, :context).new(nil, nil, nil)
      tool = described_class.for_agent(runtime_subagent, parent_chat:)

      allow(runtime_subagent).to receive(:ask).with("write code", parent_chat:).and_return("answer")

      expect(tool.execute(question: "write code")).to eq("answer")
      expect(runtime_subagent).to have_received(:ask).with("write code", parent_chat:)
    end

    it "falls back to the parent agent runtime model and context when the chat lacks explicit values" do
      runtime_subagent = build(:agent, name: "Code Assistant", llm_config_source: "runtime", model_id: nil)
      parent_agent = build(:agent, model_id: "gpt-4.1")
      llm_context = Object.new
      allow(parent_agent).to receive_messages(resolved_model_id: "gpt-4.1", resolve_llm_context: llm_context)
      parent_chat = Struct.new(:model, :agent, :context).new(nil, parent_agent, nil)
      tool = described_class.for_agent(runtime_subagent, parent_chat:)

      allow(runtime_subagent).to receive(:ask).with(
        "write code",
        parent_chat:,
        model_id: "gpt-4.1",
        llm_context:,
      ).and_return("answer")

      expect(tool.execute(question: "write code")).to eq("answer")
      expect(runtime_subagent).to have_received(:ask).with(
        "write code",
        parent_chat:,
        model_id: "gpt-4.1",
        llm_context:,
      )
    end

    it "handles runtime subagents without a parent chat" do
      runtime_subagent = build(:agent, name: "Code Assistant", llm_config_source: "runtime", model_id: nil)
      tool = described_class.for_agent(runtime_subagent)

      allow(runtime_subagent).to receive(:ask).with("write code", parent_chat: nil).and_return("answer")

      expect(tool.execute(question: "write code")).to eq("answer")
      expect(runtime_subagent).to have_received(:ask).with("write code", parent_chat: nil)
    end

    it "derives current skill catalog input values for skill-catalog-aware subagents" do
      current_skill_catalog = build_stubbed(
        :skill_catalog,
        name: "Operations Skills",
        description: "Knowledge for the operations team",
      )
      skill_catalog_designer = build(:agent, name: "Skill Catalog Designer",
                                             builtin_key: "skill_catalog_designer",
                                             input_schema: skill_catalog_input_schema,)
      runtime_context = expect_skill_catalog_designer_call(
        skill_catalog_designer,
        current_skill_catalog,
        current_skill_catalog_input_values,
      )
      tool = described_class.for_agent(skill_catalog_designer, runtime_context:)

      expect(tool.execute(question: "tune this catalog")).to eq("done")
    end

    it "derives current test suite input values for test-suite-aware subagents" do
      current_test_suite = build_stubbed(
        :test_suite,
        name: "Regression Suite",
        description: "Checks the main support flow",
        suite_type: "agent",
      )
      test_suite_designer = build(
        :agent,
        name: "Test Suite Designer",
        builtin_key: "test_suite_designer",
        input_schema: test_suite_input_schema,
      )
      runtime_context = expect_test_suite_designer_call(
        test_suite_designer,
        current_test_suite,
        current_test_suite_input_values,
      )
      tool = described_class.for_agent(test_suite_designer, runtime_context:)

      expect(tool.execute(question: "tune this suite")).to eq("done")
    end

    context "when a parent chat is present" do
      let(:parent_chat) { create(:chat) }
      let(:child_chat) do
        instance_double(
          Chat,
          id: 456,
          ui_stream_channel_name: "chat_user_stream_456",
        )
      end
      let(:tool) { described_class.for_agent(subagent, parent_chat:) }

      def callbacks
        @callbacks ||= {}
      end

      before do
        allow(subagent).to receive(:build_chat).with(parent_chat:).and_return(child_chat)
        stub_streaming_child_chat(child_chat, callbacks, subagent.name)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "streams subagent chunks and tool events through the child chat", :aggregate_failures do
        metadata = instance_double(ToolCalls::Presentation, display_name: "Read mission flow", icon: "fa-book")
        tool_call = Struct.new(:id, :tool_call_id, :name).new(101, "call-1", "read_mission_flow")
        thinking_chunk, content_chunk = build_streaming_chunks
        response = instance_double(RubyLLM::Message, content: "Done")

        stub_streaming_metadata(metadata)
        allow(child_chat).to receive(:ask) do |question, &block|
          expect(question).to eq("inspect the mission")
          callbacks[:start].call(tool_call)
          block.call(thinking_chunk)
          block.call(content_chunk)
          callbacks[:complete].call("call-1", "read_mission_flow", 15)
          response
        end

        expect(tool.execute(question: "inspect the mission")).to eq("Done")
        expect(subagent).to have_received(:build_chat).with(parent_chat:)
        expect_child_chat_stream_lifecycle(child_chat)
        expect_child_chat_chunk_broadcast(child_chat, subagent.name)
        expect_child_chat_tool_event_broadcast(child_chat)
      end

      it "passes designer questions through unchanged" do
        mission_designer = build(:agent, name: "Mission Designer", builtin_key: "mission_designer")
        designer_tool = described_class.for_agent(mission_designer, parent_chat:)
        designer_child_chat = instance_double(
          Chat,
          id: 456,
          ui_stream_channel_name: "chat_user_stream_456",
        )
        designer_callbacks = {}

        allow(mission_designer).to receive(:build_chat).with(parent_chat:).and_return(designer_child_chat)
        stub_streaming_child_chat(designer_child_chat, designer_callbacks, mission_designer.name)
        allow(ActionCable.server).to receive(:broadcast)

        allow(designer_child_chat).to receive(:ask) do |question, &_block|
          expect(question).to eq("inspect the mission")
          instance_double(RubyLLM::Message, content: "Done")
        end

        expect(designer_tool.execute(question: "inspect the mission")).to eq("Done")
      end

      it "appends a structured child-result block for designer subagents" do
        designer_tool = prepare_designer_tool(
          parent_chat:,
          messages: structured_designer_messages,
          response_content: "Updated the mission.",
        )

        result = designer_tool.execute(question: "inspect the mission")

        expect(result).to include("Updated the mission.")
        expect_mission_child_result_payload(extract_child_result_payload(result))
      end

      it "backfills missing child content from the final response content" do
        response = instance_double(RubyLLM::Message, content: "Mission change ready")
        thinking_chunk = double(thinking: "Checking the mission", content: nil, tool_call?: false)

        allow(child_chat).to receive(:ask) do |_question, &block|
          block.call(thinking_chunk)
          response
        end

        tool.execute(question: "inspect the mission")

        expect(ActionCable.server).to have_received(:broadcast).with(
          child_chat.ui_stream_channel_name,
          hash_including(
            type: "chunk",
            chat_id: 456,
            content: "Mission change ready",
            kind: "content",
            agent_name: subagent.name,
          ),
        )
      end

      it "falls back to the latest meaningful child message when the final response is blank" do
        response = instance_double(RubyLLM::Message, content: "")
        child_messages = [
          instance_double(Message, role: "assistant", content: "Let me create the mission."),
          instance_double(Message, role: "tool", content: "Mission created successfully."),
          instance_double(Message, role: "assistant", content: ""),
        ]

        allow(child_chat).to receive(:messages).and_return(child_messages)
        allow(child_chat).to receive(:ask) do |_question, &_block|
          response
        end

        expect(tool.execute(question: "inspect the mission")).to eq("Mission created successfully.")
      end

      it "broadcasts child application errors and returns the parent-facing failure message", :aggregate_failures do
        allow(child_chat).to receive(:ask).and_raise(StandardError, "connection refused")
        allow(Rails.logger).to receive(:error)

        result = tool.execute(question: "inspect the mission")

        expect(result).to include("I couldn't get an answer from the sub-agent")
        expect(result).to include("connection refused")
        expect(child_chat).to have_received(:idle!)
        expect(ActionCable.server).to have_received(:broadcast).with(
          child_chat.ui_stream_channel_name,
          hash_including(
            type: "error",
            chat_id: 456,
            message: "connection refused",
            agent_name: subagent.name,
          ),
        )
      end

      it "re-raises cancellation so the parent stream can stop and marks the child chat cancelled" do
        real_child_chat = create(:chat, parent_chat:, user: parent_chat.user, agent: subagent)
        content_chunk = double(content: "Done", tool_call?: false)

        allow(subagent).to receive(:build_chat).with(parent_chat:).and_return(real_child_chat)
        allow(real_child_chat).to receive(:before_tool_call_execution)
        allow(real_child_chat).to receive(:after_tool_call_execution)
        allow(ActionCable.server).to receive(:broadcast)

        allow(real_child_chat).to receive(:ask) do |_question, &block|
          parent_chat.cancelled!
          block.call(content_chunk)
        end

        expect { tool.execute(question: "inspect the mission") }.to raise_error(Chat::CancelledError)
        expect(real_child_chat.reload).to be_cancelled
      end

      it "returns an error when building the child chat fails before streaming starts" do
        allow(subagent).to receive(:build_chat).with(parent_chat:).and_raise(StandardError, "build failed")
        allow(Rails.logger).to receive(:error)

        result = tool.execute(question: "inspect the mission")

        expect(result).to include("I couldn't get an answer from the sub-agent")
        expect(result).to include("build failed")
      end

      it "streams content chunks that do not expose a thinking accessor" do
        response = instance_double(RubyLLM::Message, content: "Done")
        content_only_chunk = double(content: "Done", tool_call?: false)

        allow(child_chat).to receive(:ask) do |_question, &block|
          block.call(content_only_chunk)
          response
        end

        expect(tool.execute(question: "inspect the mission")).to eq("Done")
      end
    end

    it "returns error message on failure" do
      tool = described_class.for_agent(subagent)

      allow(subagent).to receive(:ask).and_raise(StandardError, "connection refused")
      allow(Rails.logger).to receive(:error)

      result = tool.execute(question: "test")

      expect(result).to include("I couldn't get an answer from the sub-agent")
      expect(result).to include("connection refused")
    end
  end

  describe "private helper behavior" do
    let(:tool) { described_class.for_agent(subagent) }

    it "returns the available runtime tool identifier" do
      fallback_only = Struct.new(:id).new(101)
      runtime_identifier = Struct.new(:id, :tool_call_id).new(101, "call-1")

      expect(tool.send(:streamed_tool_call_id, nil)).to be_nil
      expect(tool.send(:streamed_tool_call_id, fallback_only)).to eq(101)
      expect(tool.send(:streamed_tool_call_id, runtime_identifier)).to eq("call-1")
    end

    it "does not rebroadcast the stream phase when it is unchanged" do
      chat = instance_double(Chat)
      chunk = double(tool_call?: false, content: nil, thinking: "still thinking")

      allow(chat).to receive(:broadcast_status_update)

      expect(tool.send(:advance_stream_phase, chat, :thinking, chunk)).to eq(:thinking)
      expect(chat).not_to have_received(:broadcast_status_update)
    end

    it "returns nil for tool-call chunks and chunks with no visible content" do
      tool_call_chunk = double(tool_call?: true)
      empty_chunk = double(tool_call?: false, content: nil, thinking: nil)

      expect(tool.send(:stream_phase_for, tool_call_chunk)).to be_nil
      expect(tool.send(:stream_phase_for, empty_chunk)).to be_nil
    end

    it "skips chunk broadcasts when normalized content is empty" do
      chat = instance_double(Chat, id: 456, ui_stream_channel_name: "chat_user_stream_456")

      allow(chat).to receive(:ui_stream_payload) { |payload| payload }
      allow(ActionCable.server).to receive(:broadcast)

      tool.send(:broadcast_chunk, chat, nil)

      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "does not append blank normalized content while streaming chunks" do
      blank_chunk = Struct.new(:content).new({ text: "" })
      streamed_content = +"existing"

      allow(tool).to receive(:advance_stream_phase).and_return(:thinking)
      allow(tool).to receive(:broadcast_chunk)

      next_phase = tool.send(:stream_nested_subagent_chunk, :chat, blank_chunk, nil, streamed_content)

      expect(next_phase).to eq(:thinking)
      expect(streamed_content).to eq("existing")
    end

    it "backfills only the missing suffix when the final response extends streamed content" do
      chat = instance_double(Chat, id: 456, ui_stream_channel_name: "chat_user_stream_456")
      response = instance_double(RubyLLM::Message, content: "Mission change ready")

      allow(chat).to receive(:ui_stream_payload) { |payload| payload }
      allow(chat).to receive(:broadcast_status_update)
      allow(ActionCable.server).to receive(:broadcast)

      tool.send(:backfill_missing_stream_content, chat, response, "Mission")

      expect(chat).to have_received(:broadcast_status_update).with(phase: nil)
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(content: " change ready", kind: "content"),
      )
    end

    it "skips backfill when the final response does not extend streamed content" do
      chat = instance_double(Chat, id: 456, ui_stream_channel_name: "chat_user_stream_456")
      response = instance_double(RubyLLM::Message, content: "Different")

      allow(chat).to receive(:ui_stream_payload) { |payload| payload }
      allow(chat).to receive(:broadcast_status_update)
      allow(ActionCable.server).to receive(:broadcast)

      tool.send(:backfill_missing_stream_content, chat, response, "Mission")

      expect(chat).not_to have_received(:broadcast_status_update)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "returns early for blank plain-string backfill responses" do
      chat = instance_double(Chat)

      allow(chat).to receive(:broadcast_status_update)
      allow(ActionCable.server).to receive(:broadcast)

      tool.send(:backfill_missing_stream_content, chat, "", "Mission")

      expect(chat).not_to have_received(:broadcast_status_update)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "falls back to streamed content when the child response and history are blank" do
      chat = instance_double(Chat, messages: [])
      response = instance_double(RubyLLM::Message, content: "")

      result = tool.send(:nested_subagent_response_content, chat, response, "streamed result")

      expect(result).to eq("streamed result")
    end

    it "reads the latest meaningful child message from relation-backed chat messages" do
      ordered_messages = [
        instance_double(Message, content: "", role: "assistant"),
        instance_double(Message, content: "Tool result", role: "tool"),
      ]
      relation = instance_double(ActiveRecord::Relation, order: ordered_messages)
      messages = instance_double(ActiveRecord::Associations::CollectionProxy, where: relation)
      chat = instance_double(Chat, messages:)

      expect(tool.send(:latest_meaningful_child_message_content, chat)).to eq("Tool result")
    end

    it "ignores array-backed child messages that do not expose a role" do
      messages = [
        Object.new,
        instance_double(Message, content: "Tool result", role: "tool"),
      ]
      chat = instance_double(Chat, messages:)

      expect(tool.send(:latest_meaningful_child_message_content, chat)).to eq("Tool result")
    end

    it "normalizes hash chunk payloads using symbol and string text keys", :aggregate_failures do
      expect(tool.send(:normalized_chunk_content, { text: "symbol text" })).to eq("symbol text")
      expect(tool.send(:normalized_chunk_content, { "text" => "string text" })).to eq("string text")
      expect(tool.send(:normalized_chunk_content, { foo: "bar" })).to eq('{foo: "bar"}')
    end

    it "tolerates cancellation cleanup before a child chat exists" do
      expect do
        tool.send(:handle_nested_subagent_stream_error, nil, Chat::CancelledError.new)
      end.not_to raise_error
    end

    it "marks structured child results as blocked when tool errors are present" do
      designer_tool = described_class.for_agent(build(:agent, builtin_key: "tool_designer"))
      chat = instance_double(
        Chat,
        messages: [
          instance_double(Message, role: "tool", content: "Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}"),
        ],
      )

      payload = designer_tool.send(:structured_child_result_payload, chat)

      expect(payload).to include(
        "status" => "blocked",
        "record_ids" => [],
        "warnings" => [],
        "blockers" => ["Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}"],
      )
    end

    it "omits skill catalog input values that were not requested" do
      current_skill_catalog = build_stubbed(:skill_catalog, name: "Operations Skills", description: "Knowledge")
      designer_tool = described_class.for_agent(
        build(:agent, builtin_key: "skill_catalog_designer"),
        runtime_context: { current_skill_catalog: },
      )

      expect(designer_tool.send(:skill_catalog_input_values, ["other_value"])).to eq({})
    end

    it "omits test suite input values that were not requested" do
      current_test_suite = build_stubbed(:test_suite, name: "Regression Suite", description: "Checks the flow")
      designer_tool = described_class.for_agent(
        build(:agent, builtin_key: "test_suite_designer"),
        runtime_context: { current_test_suite: },
      )

      expect(designer_tool.send(:test_suite_input_values, ["other_value"])).to eq({})
    end

    it "loads relation-backed child messages and filters array-backed messages without roles", :aggregate_failures do
      tool_message = instance_double(Message, role: "tool", content: "done")
      relation = instance_double(ActiveRecord::Relation, order: [tool_message])
      relation_messages = instance_double(ActiveRecord::Associations::CollectionProxy, where: relation)
      relation_chat = instance_double(Chat, messages: relation_messages)
      array_chat = instance_double(Chat, messages: [Object.new, tool_message])

      expect(tool.send(:child_messages, relation_chat).map(&:content)).to eq(["done"])
      expect(tool.send(:child_messages, array_chat).map(&:content)).to eq(["done"])
    end

    it "returns nil for unknown or incomplete runtime record results", :aggregate_failures do
      expect(tool.send(:parse_runtime_record_result, "Unknown record updated successfully.\n- ID: `42`")).to be_nil
      expect(tool.send(:parse_runtime_record_result, "Mission updated successfully.")).to be_nil
      expect(tool.send(:parse_runtime_record_result, "Mission updated successfully.\n- ID: `42`"))
        .to include("resource" => "mission", "id" => "42", "action" => "updated")
      expect(tool.send(:runtime_record_identifier, ["- ID: invalid"])).to be_nil
    end

    it "keeps only bullet items inside a named section" do
      content = <<~TEXT
        ## Warnings
        Note: ignore this
        - Keep this warning
      TEXT

      expect(tool.send(:section_items, content, "Warnings")).to eq(["Keep this warning"])
    end

    it "falls back to the current channel title when settings payload is blank" do
      current_channel = build_stubbed(:channel, :client, name: "Support Portal")

      allow(current_channel).to receive_messages(settings_payload: {}, title: "Fallback title")

      expect(tool.send(:resolved_channel_title, current_channel)).to eq("Fallback title")
    end

    it "derives current client input values for client-aware subagents" do
      current_client = build_stubbed(:client, name: "Acme Client", title: "Acme Portal")
      client_designer = build(:agent, name: "Client Designer", input_schema: client_input_schema)
      runtime_context = { current_client: }
      client_tool = described_class.for_agent(client_designer, runtime_context:)

      allow(client_designer).to receive(:ask)
        .with(
          "tune this client",
          parent_chat: nil,
          runtime_context:,
          input_values: { client_name: "Acme Client", client_title: "Acme Portal" },
        ).and_return("done")

      expect(client_tool.execute(question: "tune this client")).to eq("done")
    end

    it "skips derived current client values when the runtime client is invalid" do
      client_designer = build(:agent, name: "Client Designer", input_schema: client_input_schema)
      runtime_context = { current_client: Object.new }
      client_tool = described_class.for_agent(client_designer, runtime_context:)

      allow(client_designer).to receive(:ask)
        .with("tune this client", parent_chat: nil, runtime_context:)
        .and_return("done")

      expect(client_tool.execute(question: "tune this client")).to eq("done")
    end

    it "omits derived channel titles when the schema does not request them" do
      current_channel = build_stubbed(:channel, :client, name: "Support Portal")
      channel_designer = build(
        :agent,
        name: "Channel Designer",
        input_schema: [{ "variable_name" => "channel_name", "label" => "Channel Name", "field_type" => "string" }],
      )
      runtime_context = { current_channel: }
      channel_tool = described_class.for_agent(channel_designer, runtime_context:)

      allow(channel_designer).to receive(:ask)
        .with(
          "review this channel",
          parent_chat: nil,
          runtime_context:,
          input_values: { channel_name: "Support Portal" },
        ).and_return("done")

      expect(channel_tool.execute(question: "review this channel")).to eq("done")
    end

    it "omits derived current client values when the schema does not request them" do
      current_client = build_stubbed(:client, name: "Acme Client", title: "Acme Portal")
      client_designer = build(
        :agent,
        name: "Client Designer",
        input_schema: [{ "variable_name" => "other_value", "label" => "Other Value", "field_type" => "string" }],
      )
      runtime_context = { current_client: }
      client_tool = described_class.for_agent(client_designer, runtime_context:)

      allow(client_designer).to receive(:ask)
        .with("tune this client", parent_chat: nil, runtime_context:)
        .and_return("done")

      expect(client_tool.execute(question: "tune this client")).to eq("done")
    end
  end
end
