# frozen_string_literal: true

require "rails_helper"

RSpec.describe ManageRecordTool do
  let(:tenant) { Tenant.default_tenant.tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:mission) { create(:mission, operation:) }
  let(:agent_record) { create(:agent, operation:, name: "Existing Agent", model_id: "gpt-4.1") }
  let(:client_channel) do
    create(
      :channel,
      :client,
      tenant:,
      default: true,
      name: "Support Portal",
      configuration: {
        "title" => "<p>Support Portal</p>",
      },
    ).tap do |channel|
      create(:channel_target, channel:, target: agent_record, default: true)
    end
  end
  let(:sql_connector) { create(:connector, :sql_database, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:tool) { described_class.new(parent_chat: chat, mission:) }

  def expect_navigation_to(chat, path)
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(type: "navigate", chat_id: chat.id, path:),
    )
  end

  def current_page_tool_for(record)
    page_context = {
      "page" => { "path" => Rails.application.routes.url_helpers.admin_agent_path(record) },
      "current_object" => {
        "class_name" => "Agent",
        "id" => record.id,
      },
    }

    described_class.new(parent_chat: chat, mission:, ui_context: page_context)
  end

  def current_client_preview_tool_for(record)
    preview_path = Rails.application.routes.url_helpers.admin_channel_path(record, view: :preview, chat_id: 7)

    page_context = {
      "page" => { "path" => preview_path },
      "current_object" => {
        "class_name" => "Channel",
        "id" => record.id,
      },
    }

    described_class.new(parent_chat: chat, mission:, ui_context: page_context)
  end

  def current_test_suite_tool_for(record)
    suite_path = Rails.application.routes.url_helpers.admin_test_suite_path(record)

    page_context = {
      "page" => { "path" => suite_path },
      "current_object" => {
        "class_name" => "TestSuite",
        "id" => record.id,
      },
    }

    described_class.new(parent_chat: chat, mission:, ui_context: page_context)
  end

  def expect_refresh_to(chat, path)
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(type: "refresh", chat_id: chat.id, path:),
    )
  end

  def agent_input_schema_payload
    [{
      variable_name: "task",
      label: "Task",
      field_type: "string",
      required: true,
    }]
  end

  def expected_agent_input_schema
    [{
      "variable_name" => "task",
      "label" => "Task",
      "field_type" => "string",
      "required" => true,
      "config" => {},
    }]
  end

  def agent_update_payload(helper_tool:, helper_subagent:, skill_catalog:, llm_connector:)
    {
      description: "Updated by the builtin agent designer",
      assigned_tool_ids: [helper_tool.id],
      subagent_ids: [helper_subagent.id],
      skill_catalog_ids: [skill_catalog.id],
      input_schema: agent_input_schema_payload,
      custom_llm_params: { "top_p" => 0.4 },
      model_routing_config: {
        strategy: "fallback",
        fallback_models: [{ connector_id: llm_connector.id, model_id: "gpt-4.1-mini" }],
      },
    }
  end

  def tool_create_payload(connector_id)
    {
      tool_type: "sql_query",
      name: "Orders Explorer",
      description: "Reads the order catalog",
      toolable_attributes: {
        connector_id:,
        llm_config_source: "inherit",
      },
    }
  end

  def client_channel_create_payload(agent_id)
    {
      name: "Support Portal",
      channel_type: "client",
      agent_id:,
      title: "<p>Support Portal</p>",
      new_chat_label: "Start now",
    }
  end

  def expect_sql_tool_configuration(tool_record, connector_id)
    expect(tool_record.configuration).to include(
      "connector_id" => connector_id,
      "llm_config_source" => "inherit",
    )
  end

  describe "#execute" do
    it "creates a mission in the current operation and broadcasts Turbo navigation", :aggregate_failures do
      allow(ActionCable.server).to receive(:broadcast)
      mission
      tool

      expect do
        result = tool.execute(
          resource: "mission",
          action: "create",
          attributes: { name: "Created From Tool", description: "Runtime-created mission" },
        )

        expect(result).to include("Mission created successfully.")
        expect(result).to include("Continue same-turn mission edits by passing the returned ID as `mission_id`.")
      end.to change { Mission.where(operation:).count }.by(1)

      created_mission = Mission.order(:id).last
      expect_navigation_to(chat, Rails.application.routes.url_helpers.designer_admin_mission_path(created_mission))
    end

    it "returns an error when create is missing attributes" do
      expect(tool.execute(resource: "mission", action: "create")).to eq("Error: Provide attributes for create.")
    end

    it "returns validation errors from failed creates" do
      result = tool.execute(resource: "mission", action: "create", attributes: { name: "" })

      expect(result).to eq("Error: Name can't be blank")
    end

    it "updates a mission inside the current operation" do
      result = tool.execute(
        resource: "mission",
        action: "update",
        record_id: mission.id,
        attributes: { name: "Updated By Tool" },
      )

      expect(result).to include("Mission updated successfully.")
      expect(mission.reload.name).to eq("Updated By Tool")
    end

    it "creates a test suite and broadcasts Turbo navigation", :aggregate_failures do
      allow(ActionCable.server).to receive(:broadcast)

      expect do
        result = tool.execute(
          resource: "test_suite",
          action: "create",
          attributes: {
            name: "Regression Smoke",
            description: "Checks the primary support flow",
            suite_type: "agent",
            agent_id: agent_record.id,
          },
        )

        expect(result).to include("Test Suite created successfully.")
      end.to change(TestSuite, :count).by(1)

      created_suite = TestSuite.order(:id).last
      expect(created_suite.agent).to eq(agent_record)
      expect_navigation_to(chat, Rails.application.routes.url_helpers.admin_test_suite_path(created_suite))
    end

    it "updates a test suite and refreshes the current page when navigation is not requested", :aggregate_failures do
      suite = create(:test_suite, agent: agent_record, name: "Smoke")
      allow(ActionCable.server).to receive(:broadcast)
      suite_tool = current_test_suite_tool_for(suite)

      result = suite_tool.execute(
        resource: "test_suite",
        action: "update",
        record_id: suite.id,
        navigate: false,
        attributes: { description: "Updated from the shared application chat" },
      )

      expect(result).to include("Test Suite updated successfully.")
      expect(suite.reload.description).to eq("Updated from the shared application chat")
      expect_refresh_to(chat, Rails.application.routes.url_helpers.admin_test_suite_path(suite))
    end

    it "creates an agent in the current operation and broadcasts Turbo navigation", :aggregate_failures do
      allow(ActionCable.server).to receive(:broadcast)

      expect do
        result = tool.execute(
          resource: "agent",
          action: "create",
          attributes: {
            name: "Designed Agent",
            description: "Created from the builtin agent designer",
            model_id: "gpt-4.1",
          },
        )

        expect(result).to include("Agent created successfully.")
        expect(result).to include("Wait for the next turn before editing the newly opened record.")
      end.to change { Agent.where(operation:).count }.by(1)

      created_agent = Agent.order(:id).last
      expect(created_agent.configuration["agent_type"]).to eq(AgentConfiguration::DEFAULT_AGENT_TYPE)
      expect_navigation_to(chat, Rails.application.routes.url_helpers.admin_agent_path(created_agent))
    end

    it "preserves an explicit agent type when provided on create" do
      allow(ActionCable.server).to receive(:broadcast)

      tool.execute(
        resource: "agent",
        action: "create",
        attributes: {
          name: "Specialized Agent",
          description: "Created from the builtin agent designer",
          model_id: "gpt-4.1",
          agent_type: "code_assistant",
        },
      )

      created_agent = Agent.order(:id).last
      expect(created_agent.configuration["agent_type"]).to eq("code_assistant")
    end

    it "defaults agent designer creates back to general when the user did not request a type" do
      allow(ActionCable.server).to receive(:broadcast)
      chat.messages.create!(role: :user, content: "Create an agent for summarizing tickets")
      agent_designer = create(:agent, operation:, name: "Agent Designer", agent_type: "agent_designer")
      agent_designer_tool = described_class.new(agent: agent_designer, parent_chat: chat, mission:)

      agent_designer_tool.execute(
        resource: "agent",
        action: "create",
        attributes: {
          name: "Ticket Summarizer",
          model_id: "gpt-4.1",
          agent_type: "mission_designer",
        },
      )

      created_agent = Agent.order(:id).last
      expect(created_agent.configuration["agent_type"]).to eq(AgentConfiguration::DEFAULT_AGENT_TYPE)
    end

    it "preserves an explicitly requested non-general type for agent designer creates" do
      allow(ActionCable.server).to receive(:broadcast)
      chat.messages.create!(role: :user, content: "Create an agent with agent type mission_designer")
      agent_designer = create(:agent, operation:, name: "Agent Designer", agent_type: "agent_designer")
      agent_designer_tool = described_class.new(agent: agent_designer, parent_chat: chat, mission:)

      agent_designer_tool.execute(
        resource: "agent",
        action: "create",
        attributes: {
          name: "Mission Helper",
          model_id: "gpt-4.1",
          agent_type: "mission_designer",
        },
      )

      created_agent = Agent.order(:id).last
      expect(created_agent.configuration["agent_type"]).to eq("mission_designer")
    end

    it "defaults provider-like type requests back to general for agent designer creates" do
      allow(ActionCable.server).to receive(:broadcast)
      chat.messages.create!(role: :user, content: "Create an OpenAI-powered agent for support triage")
      agent_designer = create(:agent, operation:, name: "Agent Designer", agent_type: "agent_designer")
      agent_designer_tool = described_class.new(agent: agent_designer, parent_chat: chat, mission:)

      agent_designer_tool.execute(
        resource: "agent",
        action: "create",
        attributes: {
          name: "Support Triage",
          model_id: "gpt-4.1",
          agent_type: "openai",
        },
      )

      created_agent = Agent.order(:id).last
      expect(created_agent.configuration["agent_type"]).to eq(AgentConfiguration::DEFAULT_AGENT_TYPE)
    end

    it "updates agent configuration fields and replacement arrays" do
      helper_tool = create(:tool, :mission_tool, :enabled, operation:, name: "Agent Helper")
      helper_subagent = create(:agent, :enabled, operation:, name: "Research Wing", model_id: "gpt-4.1")
      skill_catalog = create(:skill_catalog, operation:, name: "Agent Playbook")
      llm_connector = create(:connector, :llm_provider, :enabled, tenant:, name: "Primary LLM")

      result = tool.execute(
        resource: "agent",
        action: "update",
        record_id: agent_record.id,
        attributes: agent_update_payload(helper_tool:, helper_subagent:, skill_catalog:, llm_connector:),
      )

      updated_agent = agent_record.reload

      expect(result).to include("Agent updated successfully.")
      expect(updated_agent).to have_attributes(
        description: "Updated by the builtin agent designer",
        assigned_tool_ids: [helper_tool.id],
        subagent_ids: [helper_subagent.id],
        skill_catalog_ids: [skill_catalog.id],
        custom_llm_params: { "top_p" => 0.4 },
        model_routing_config: {
          "strategy" => "fallback",
          "fallback_models" => [{ "connector_id" => llm_connector.id, "model_id" => "gpt-4.1-mini" }],
        },
      )
      expect(updated_agent.input_schema).to eq(expected_agent_input_schema)
    end

    it "refreshes the current agent page after an in-place update" do
      allow(ActionCable.server).to receive(:broadcast)
      current_page_tool = current_page_tool_for(agent_record)

      result = current_page_tool.execute(
        resource: "agent",
        action: "update",
        record_id: agent_record.id,
        attributes: { description: "Refreshed in place" },
      )

      expect(result).to include("Agent updated successfully.")
      expect(result).to include("Current page refresh started")
      expect_refresh_to(chat, Rails.application.routes.url_helpers.admin_agent_path(agent_record))
    end

    it "returns an error when update is missing required inputs", :aggregate_failures do
      expect(tool.execute(resource: "mission", action: "update")).to eq("Error: Provide record_id for update.")
      expect(tool.execute(resource: "mission", action: "update", record_id: mission.id)).to eq(
        "Error: Provide attributes for update.",
      )
    end

    it "updates a mission and resolves a custom follow-up page" do
      result = tool.execute(
        resource: "mission",
        action: "update",
        record_id: mission.id,
        attributes: { name: "Updated To Edit" },
        page: "edit",
      )

      expect(result).to include("Mission updated successfully.")
      expect(result).to include(
        "- Path: `#{Rails.application.routes.url_helpers.edit_admin_mission_path(mission.reload)}`",
      )
    end

    it "clones a mission and returns same-turn designer guidance", :aggregate_failures do
      allow(ActionCable.server).to receive(:broadcast)

      result = tool.execute(resource: "mission", action: "clone", record_id: mission.id)

      cloned_mission = Mission.order(:id).last
      expect(result).to include("Mission cloned successfully.")
      expect(result).to include("Continue same-turn mission edits by passing the returned ID as `mission_id`.")
      expect(cloned_mission.name).to start_with("Clone of ")
      expect_navigation_to(chat, Rails.application.routes.url_helpers.designer_admin_mission_path(cloned_mission))
    end

    it "clones a mission and resolves a custom follow-up page" do
      result = tool.execute(resource: "mission", action: "clone", record_id: mission.id, page: "edit")
      cloned_mission = Mission.order(:id).last
      expected_path = Rails.application.routes.url_helpers.edit_admin_mission_path(cloned_mission)

      expect(result).to include("Mission cloned successfully.")
      expect(result).to include("- Path: `#{expected_path}`")
    end

    it "returns a clear error when clone is unsupported for the resource" do
      skill_catalog = create(:skill_catalog, operation:, name: "Support")

      result = tool.execute(resource: "skill_catalog", action: "clone", record_id: skill_catalog.id)

      expect(result).to eq("Error: Clone is not supported for skill catalogs.")
    end

    it "requires a record id for clone" do
      expect(tool.execute(resource: "mission", action: "clone")).to eq("Error: Provide record_id for clone.")
    end

    it "requires explicit delete confirmation" do
      result = tool.execute(resource: "mission", action: "delete", record_id: mission.id)

      expect(result).to eq("Error: confirm_destroy must be true for delete actions.")
      expect(Mission.exists?(mission.id)).to be(true)
    end

    it "returns an error when delete is missing the record id" do
      expect(tool.execute(resource: "mission", action: "delete")).to eq("Error: Provide record_id for delete.")
    end

    it "deletes a mission and navigates back to the index" do
      allow(ActionCable.server).to receive(:broadcast)

      result = tool.execute(
        resource: "mission",
        action: "delete",
        record_id: mission.id,
        confirm_destroy: true,
      )

      expect(result).to include("Mission deleted successfully.")
      expect(result).to include("Turbo navigation started back to the resource index.")
      expect(Mission.exists?(mission.id)).to be(false)
      expect_navigation_to(chat, Rails.application.routes.url_helpers.admin_missions_path)
    end

    it "deletes a mission and resolves a custom collection page" do
      result = tool.execute(
        resource: "mission",
        action: "delete",
        record_id: mission.id,
        confirm_destroy: true,
        page: "new",
      )

      expect(result).to include("Mission deleted successfully.")
      expect(result).to include("- Path: `#{Rails.application.routes.url_helpers.new_admin_mission_path}`")
    end

    it "does not reach missions outside the current operation" do
      other_operation = create(:operation, tenant:)
      other_mission = create(:mission, operation: other_operation)

      result = tool.execute(
        resource: "mission",
        action: "update",
        record_id: other_mission.id,
        attributes: { name: "Should Not Work" },
      )

      expect(result).to eq("Error: Mission '#{other_mission.id}' was not found.")
      expect(other_mission.reload.name).not_to eq("Should Not Work")
    end

    it "returns the shared read-only message for Headquarter mutations" do
      headquarter_mission = create(:mission, operation: tenant.headquarter_operation)
      headquarter_tool = described_class.new(parent_chat: chat, mission: headquarter_mission)
      result = nil

      expect do
        result = headquarter_tool.execute(
          resource: "mission",
          action: "create",
          attributes: { name: "Blocked Headquarter Mission" },
        )
      end.not_to(change { Mission.where(operation: tenant.headquarter_operation).count })
      expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
    end

    it "can return a manual navigation note outside the shared application chat" do
      allow(RuntimeRecords::Navigation).to receive(:broadcast!).and_return(:skipped)

      result = tool.execute(
        resource: "mission",
        action: "create",
        attributes: { name: "Manual Follow Up" },
        page: "edit",
      )

      expect(result).to include("Mission created successfully.")
      expect(result).to include("Navigation was not broadcast.")
    end

    it "rejects unknown actions" do
      expect(tool.execute(resource: "mission", action: "archive")).to eq(
        "Error: Unknown action 'archive'. Use create, clone, update, or delete.",
      )
    end

    it "returns unexpected tool errors with context" do
      broken_manager = instance_double(RuntimeRecords::Manager)
      allow(RuntimeRecords::Manager).to receive(:new).and_return(broken_manager)
      allow(broken_manager).to receive(:create).and_raise(StandardError, "boom")

      result = tool.execute(resource: "mission", action: "create", attributes: { name: "Explode" })

      expect(result).to eq("Failed to manage mission: boom")
    end

    it "creates a tool and broadcasts Turbo navigation", :aggregate_failures do
      allow(ActionCable.server).to receive(:broadcast)

      expect do
        result = tool.execute(resource: "tool", action: "create", attributes: tool_create_payload(sql_connector.id))

        expect(result).to include("Tool created successfully.")
        expect(result).to include("Wait for the next turn before editing the newly opened record.")
      end.to change { Tool.where(operation:).count }.by(1)

      created_tool = Tool.order(:id).last
      expect(created_tool.tool_type).to eq("sql_query")
      expect_sql_tool_configuration(created_tool, sql_connector.id)
      expect_navigation_to(chat, Rails.application.routes.url_helpers.admin_tool_path(created_tool))
    end

    it "creates a client channel and opens the preview by default", :aggregate_failures do
      allow(ActionCable.server).to receive(:broadcast)
      client_agent = create(:agent, operation:, name: "Client Agent", model_id: "gpt-4.1")

      expect do
        result = tool.execute(
          resource: "channel",
          action: "create",
          attributes: client_channel_create_payload(client_agent.id),
        )

        expect(result).to include("Channel created successfully.")
        expect(result).to include("Wait for the next turn before editing the newly opened record.")
      end.to change { Channel.where(tenant:, channel_type: "client").count }.by(1)

      created_channel = Channel.order(:id).last
      expect(created_channel.new_chat_label).to eq("Start now")
      expect(created_channel.client_agent).to eq(client_agent)
      expect_navigation_to(
        chat,
        Rails.application.routes.url_helpers.admin_channel_path(created_channel, view: :preview),
      )
    end

    it "refreshes the current client-channel preview after an in-place update" do
      allow(ActionCable.server).to receive(:broadcast)
      current_preview_tool = current_client_preview_tool_for(client_channel)

      result = current_preview_tool.execute(
        resource: "channel",
        action: "update",
        record_id: client_channel.id,
        attributes: { new_chat_label: "Start now" },
      )

      expect(result).to include("Channel updated successfully.")
      expect(result).to include("Current page refresh started")
      preview_path = Rails.application.routes.url_helpers.admin_channel_path(client_channel, view: :preview, chat_id: 7)

      expect_refresh_to(chat, preview_path)
    end

    it "updates a tool with nested toolable attributes" do
      tool_record = create(
        :tool,
        operation:,
        name: "Orders Explorer",
        toolable: Tools::SqlQuery.new(connector_id: sql_connector.id, llm_config_source: "inherit"),
      )

      result = tool.execute(
        resource: "tool",
        action: "update",
        record_id: tool_record.id,
        attributes: {
          description: "Updated by the tool designer",
          toolable_attributes: { instructions: "Use this tool for reporting only." },
        },
      )

      expect(result).to include("Tool updated successfully.")
      expect(tool_record.reload.description).to eq("Updated by the tool designer")
      expect(tool_record.configuration["instructions"]).to eq("Use this tool for reporting only.")
    end

    it "deletes a tool and navigates back to the index" do
      allow(ActionCable.server).to receive(:broadcast)
      tool_record = create(
        :tool,
        operation:,
        name: "Orders Explorer",
        toolable: Tools::SqlQuery.new(connector_id: sql_connector.id, llm_config_source: "inherit"),
      )

      result = tool.execute(
        resource: "tool",
        action: "delete",
        record_id: tool_record.id,
        confirm_destroy: true,
      )

      expect(result).to include("Tool deleted successfully.")
      expect(Tool.exists?(tool_record.id)).to be(false)
      expect_navigation_to(chat, Rails.application.routes.url_helpers.admin_tools_path)
    end
  end

  describe "private helpers" do
    it "honors explicit navigation flags and blank paths", :aggregate_failures do
      expect(tool.send(:requested_navigation?, { navigate: false }, default: true)).to be(false)
      expect(tool.send(:perform_navigation?, nil, true)).to be(false)
    end

    it "covers agent create normalization edge cases", :aggregate_failures do
      agent_designer = create(:agent, operation:, name: "Agent Designer", agent_type: "agent_designer")
      agent_designer_tool = described_class.new(agent: agent_designer, parent_chat: chat, mission:)

      blank_type_attributes = { name: "Blank Type", agent_type: nil }
      default_type_attributes = { name: "Default Type", agent_type: AgentConfiguration::DEFAULT_AGENT_TYPE }
      non_object_json = '["mission_designer"]'

      expect(agent_designer_tool.send(:normalize_create_attributes, "agent", blank_type_attributes)).to eq(
        blank_type_attributes.stringify_keys,
      )
      expect(agent_designer_tool.send(:normalize_create_attributes, "agent", default_type_attributes)).to eq(
        default_type_attributes.stringify_keys,
      )
      expect(agent_designer_tool.send(:normalize_create_attributes, "agent", non_object_json)).to eq(non_object_json)
    end

    it "parses normalization attributes across supported input types", :aggregate_failures do
      parameters = ActionController::Parameters.new(name: "Param Agent")
      string_payload = '{"agent_type":"mission_designer"}'

      expect(tool.send(:parse_attributes_for_normalization, parameters)).to eq({ "name" => "Param Agent" })
      expect(tool.send(:parse_attributes_for_normalization, string_payload)).to eq(
        { "agent_type" => "mission_designer" },
      )
      expect(tool.send(:parse_attributes_for_normalization, 123)).to eq(123)
    end

    it "returns blank request text without a chat or user messages", :aggregate_failures do
      agent_designer = create(:agent, operation:, name: "Agent Designer", agent_type: "agent_designer")
      tool_without_chat = described_class.new(agent: agent_designer, mission:)
      empty_chat_tool = described_class.new(
        agent: agent_designer,
        parent_chat: create(:chat, :application_context, user:),
        mission:,
      )

      expect(tool_without_chat.send(:latest_user_request_text)).to eq("")
      expect(tool_without_chat.send(:explicit_agent_type_request?, "mission_designer")).to be(false)
      expect(empty_chat_tool.send(:latest_user_request_text)).to eq("")
    end

    it "returns no navigation note for unsupported actions without an application chat" do
      non_application_tool = described_class.new

      expect(
        non_application_tool.send(:navigation_note, :archive, path: "/admin/missions", navigated: true),
      ).to be_nil
      expect(
        non_application_tool.send(:navigation_note, :update, path: "/admin/missions", navigated: false),
      ).to be_nil
    end

    it "returns no navigation note when a non-application chat cannot navigate" do
      non_application_chat = create(:chat, user:)
      allow(non_application_chat).to receive(:application?).and_return(false)
      non_application_tool = described_class.new(parent_chat: non_application_chat, mission:)

      expect(
        non_application_tool.send(:navigation_note, :update, path: "/admin/missions", navigated: false),
      ).to be_nil
    end

    it "does not refresh when a mutation result has no persisted record" do
      allow(RuntimeRecords::Refresh).to receive(:broadcast!)
      result = Struct.new(:record).new(nil)

      expect(tool.send(:perform_refresh?, resource: "mission", result:, navigated: false)).to be(false)
      expect(RuntimeRecords::Refresh).not_to have_received(:broadcast!)
    end

    it "falls back to the raw action name for unknown tenses" do
      expect(tool.send(:past_tense_for, :archive)).to eq("archive")
    end
  end
end
