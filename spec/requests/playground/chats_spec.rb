# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground::Chats", :unauthenticated do
  # Use a known user so we can associate chats with the signed-in user.
  let(:user) { create(:user, :admin, tenant: default_tenant) }

  # Create a model record matching the agent factory's model_id ("gpt-4.1")
  # so that resolve_model_from_strings doesn't try to hit the RubyLLM API.
  # Override the auto-sign-in with our controlled user.
  before do
    create(:model, model_id: "gpt-4.1", provider: "openai")
    sign_in(user)
  end

  describe "GET /playground/chats" do
    it "returns a successful response" do
      get admin_playground_chats_path
      expect(response).to have_http_status(:ok)
    end

    it "displays the playground title" do
      get admin_playground_chats_path
      expect(response.body).to include("Playground")
    end

    it "shows the empty state when no compatible agent is available" do
      get admin_playground_chats_path
      expect(response.body).to include("No available agents for this operation")
      expect(response.body).to include(I18n.t("playground.chats.no_available_agents.description"))
      expect(response.body).to include("shared-chat__empty-state")
    end

    context "with an agent selected" do
      let(:agent) { create(:agent) }

      it "redirects to a new chat when agent has no chats" do
        get admin_playground_chats_path, params: { agent_id: agent.id }
        expect(response).to redirect_to(admin_playground_chat_path(Chat.last))
      end

      it "redirects to the most recent chat when agent has chats" do
        chat = create(:chat, agent:, user:)
        get admin_playground_chats_path, params: { agent_id: agent.id }
        expect(response).to redirect_to(admin_playground_chat_path(chat))
      end

      it "does not redirect to chats belonging to other users" do
        _other_chat = create(:chat, agent:, user: create(:user))
        get admin_playground_chats_path, params: { agent_id: agent.id }
        # No chat for current user → creates a new one
        expect(response).to redirect_to(admin_playground_chat_path(Chat.last))
        expect(Chat.last.user).to eq(user)
      end
    end

    it "does not auto-create a chat when agents exist but none is selected" do
      create(:agent, name: "Test Agent Alpha", enabled: true)

      expect do
        get admin_playground_chats_path
      end.not_to change(Chat, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Select an agent to start chatting")
    end

    it "lists agents with user-assignable built-in tools as available" do
      agent = create(:agent, enabled: true)
      agent.update!(runtime_tool_keys: ["web.web_search"])

      get admin_playground_chats_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(agent.name)
      expect(response.body).to include("Select an agent to start chatting")
    end

    it "does not list agents with non-user-assignable built-in tools as available" do
      agent = create(:agent, enabled: true)
      agent.update!(runtime_tool_keys: ["mission_designer.validate_flow"])

      get admin_playground_chats_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No available agents for this operation")
      expect(response.body).to include(I18n.t("playground.chats.no_available_agents.description"))
      expect(response.body).not_to include(agent.name)
    end

    it "redirects to most recent chat when no agent_id param but chats exist" do
      agent = create(:agent, enabled: true)
      existing_chat = create(:chat, agent:, user:)

      get admin_playground_chats_path
      expect(response).to redirect_to(admin_playground_chat_path(existing_chat))
    end
  end

  describe "GET /playground/chats/:id" do
    let(:agent) { create(:agent) }
    let(:chat) { create(:chat, agent:, user:) }
    let(:persisted_hitl_tool_call_arguments) do
      Capabilities::HumanInTheLoop::ToolCallState.build(
        prompt_text: "Need one clarification before I query the database.",
        raw_questions: [{ prompt: "What should I search for?", options: ["Customers", "Invoices"] }],
        capability: build(:capabilities_human_in_the_loop_standalone),
      ).to_h
    end

    def create_persisted_hitl_tool_call(message:, arguments:)
      create(
        :tool_call,
        message:,
        name: "ask_user_questions",
        display_name: "Ask User Questions",
        icon: "fa-solid fa-circle-question",
        arguments:,
      )
    end

    it "returns a successful response" do
      get admin_playground_chat_path(chat)
      expect(response).to have_http_status(:ok)
    end

    it "displays the chat" do
      get admin_playground_chat_path(chat)
      expect(response.body).to include(chat.display_title)
    end

    it "displays the agent name" do
      get admin_playground_chat_path(chat)
      expect(response.body).to include(agent.name)
    end

    it "shows the message input" do
      get admin_playground_chat_path(chat)
      expect(response.body).to include("Type your message")
      expect(response.body).to include("shared-chat__composer")
    end

    it "returns turbo-stream catch-up updates" do
      get admin_playground_chat_path(chat, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="update"')
      expect(response.body).to include("target=\"chat-#{chat.id}-messages\"")
      expect(response.body).to include("chat-#{chat.id}-status")
    end

    it "renders persisted HITL widgets in turbo-stream catch-up responses" do
      assistant_message = create(:message, chat:, role: :assistant, content: nil)
      create_persisted_hitl_tool_call(message: assistant_message, arguments: persisted_hitl_tool_call_arguments)

      get admin_playground_chat_path(chat, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        "shared-chat__message--stable",
        "Need Your Input",
        "What should I search for?",
        "Send",
      )
      expect(response.body).not_to include("shared-chat__tool-call-icon-wrap")
    end

    context "with messages" do
      it "displays existing messages" do
        create(:message, chat:, role: :user, content: "Hello there")
        get admin_playground_chat_path(chat)
        expect(response.body).to include("Hello there")
      end
    end

    context "when chat has no agent (nil agent)" do
      let(:chat_no_agent) { create(:chat, agent: nil, user:) }

      it "redirects back to the playground index" do
        get admin_playground_chat_path(chat_no_agent)
        expect(response).to redirect_to(admin_playground_chats_path)
      end
    end

    context "when the chat agent uses a user-assignable built-in tool" do
      let(:agent) do
        create(:agent).tap do |record|
          record.update!(runtime_tool_keys: ["web.web_search"])
        end
      end
      let(:chat) { create(:chat, agent:, user:) }

      it "renders the playground chat" do
        get admin_playground_chat_path(chat)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(agent.name)
      end

      it "returns turbo-stream catch-up updates" do
        get admin_playground_chat_path(chat, format: :turbo_stream)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    context "when the chat agent uses a non-user-assignable built-in tool" do
      let(:agent) do
        create(:agent).tap do |record|
          record.update!(runtime_tool_keys: ["mission_designer.validate_flow"])
        end
      end
      let(:chat) { create(:chat, agent:, user:) }

      it "redirects back to the playground index" do
        get admin_playground_chat_path(chat)

        expect(response).to redirect_to(admin_playground_chats_path)
      end

      it "returns not found for turbo-stream requests" do
        get admin_playground_chat_path(chat, format: :turbo_stream)

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the chat belongs to another user" do
      let(:other_chat) { create(:chat, agent:, user: create(:user)) }

      it "returns not found" do
        get admin_playground_chat_path(other_chat)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /playground/chats" do
    let(:agent) { create(:agent) }

    it "creates a new chat" do
      expect do
        post admin_playground_chats_path, params: { agent_id: agent.id }
      end.to change(Chat, :count).by(1)
    end

    it "associates the chat with the agent" do
      post admin_playground_chats_path, params: { agent_id: agent.id }
      expect(Chat.last.agent).to eq(agent)
    end

    it "associates the chat with the current user" do
      post admin_playground_chats_path, params: { agent_id: agent.id }
      expect(Chat.last.user).to eq(user)
    end

    it "creates the chat with playground execution_context" do
      post admin_playground_chats_path, params: { agent_id: agent.id }
      expect(Chat.last.execution_context).to eq("playground")
    end

    it "redirects to the new chat" do
      post admin_playground_chats_path, params: { agent_id: agent.id }
      expect(response).to redirect_to(admin_playground_chat_path(Chat.last))
    end

    it "creates chats for agents with user-assignable built-in tools" do
      agent.update!(runtime_tool_keys: ["web.web_search"])

      expect do
        post admin_playground_chats_path, params: { agent_id: agent.id }
      end.to change(Chat, :count).by(1)

      expect(response).to redirect_to(admin_playground_chat_path(Chat.last))
    end

    it "rejects agents with non-user-assignable built-in tools" do
      agent.update!(runtime_tool_keys: ["mission_designer.validate_flow"])

      expect do
        post admin_playground_chats_path, params: { agent_id: agent.id }
      end.not_to change(Chat, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "falls back to Model.first when agent model_id is not found" do
      unknown_agent = create(:agent, model_id: "unknown-model-xyz")
      post admin_playground_chats_path, params: { agent_id: unknown_agent.id }
      expect(Chat.last.model).to eq(Model.first)
    end
  end

  describe "DELETE /playground/chats/:id" do
    let(:agent) { create(:agent) }
    let!(:chat) { create(:chat, agent:, user:) }

    it "deletes the chat" do
      expect do
        delete admin_playground_chat_path(chat)
      end.to change(Chat, :count).by(-1)
    end

    it "redirects to the playground index" do
      delete admin_playground_chat_path(chat)
      expect(response).to redirect_to(admin_playground_chats_path)
    end
  end

  describe "POST /playground/chats/:id/cancel" do
    let(:agent) { create(:agent) }
    let(:chat) { create(:chat, agent:, user:, status: "streaming") }

    it "cancels the chat" do
      post cancel_admin_playground_chat_path(chat)
      expect(chat.reload.status).to eq("cancelled")
    end

    it "returns success status" do
      post cancel_admin_playground_chat_path(chat)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /playground/chats/more" do
    let(:agent) { create(:agent) }

    before { create_list(:chat, 10, agent:, user:) }

    it "returns turbo stream content" do
      get more_admin_playground_chats_path,
          params: { agent_id: agent.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("turbo-stream")
    end

    it "paginates chats on page 2" do
      get more_admin_playground_chats_path,
          params: { agent_id: agent.id, page: 2 },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
    end

    it "does not include chats from other users" do
      create(:chat, agent:, user: create(:user))
      get more_admin_playground_chats_path,
          params: { agent_id: agent.id, page: 2 },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
    end
  end
end
