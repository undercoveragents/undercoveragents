# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inspector::Chats" do
  before { create(:model, model_id: "gpt-4.1", provider: "openai") }

  def response_document
    response.parsed_body
  end

  let(:agent) { create(:agent) }
  let(:model_record) { Model.find_by(model_id: "gpt-4.1") }

  def referenced_message_content
    ChatReferences::MessagePayload.pack(
      content: "Update #echo-test",
      references: [
        {
          "kind" => "missions",
          "type" => "Mission",
          "id" => 30,
          "label" => "Echo Test",
          "slug" => "echo-test",
        },
      ],
    )
  end

  describe "GET /inspector/chats" do
    it "returns a successful response when no chats exist" do
      get admin_inspector_chats_path
      expect(response).to have_http_status(:ok)
    end

    it "displays the inspector title" do
      get admin_inspector_chats_path
      expect(response.body).to include("Agents inspector")
    end

    it "shows the empty state when no chats exist" do
      get admin_inspector_chats_path
      expect(response.body).to include("No chats found")
    end

    context "when chats exist" do
      let!(:chat) { create(:chat, agent:, model: model_record, title: "Test Chat") }

      it "shows chat list" do
        get admin_inspector_chats_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Test Chat")
      end

      it "shows chat ID" do
        get admin_inspector_chats_path
        expect(response.body).to include(chat.id.to_s)
      end

      it "renders chat rows without hard-navigation onclick handlers", :aggregate_failures do
        get admin_inspector_chats_path

        row = response_document.at_css("tr.inspector-tr")
        title_link = response_document.at_css("a[href='#{admin_inspector_chat_path(chat)}']")

        expect(row).to be_present
        expect(row["onclick"]).to be_nil
        expect(title_link).to be_present
      end
    end

    context "with filters" do
      let!(:idle_chat) { create(:chat, agent:, model: model_record, title: "Idle Chat", status: :idle) }

      it "filters by id" do
        get admin_inspector_chats_path, params: { q: { id_eq: idle_chat.id } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Idle Chat")
      end

      it "filters by execution_context" do
        create(:chat, agent:, model: model_record, title: "Playground Chat", execution_context: :playground)
        get admin_inspector_chats_path, params: { q: { execution_context_eq: "playground" } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Playground Chat")
      end

      it "filters by title" do
        get admin_inspector_chats_path, params: { q: { title_cont: "Idle" } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Idle Chat")
      end

      it "filters by agent_id" do
        get admin_inspector_chats_path, params: { q: { agent_id_eq: agent.id } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Idle Chat")
      end

      it "filters root_only chats" do
        create(:chat, title: "Child", parent_chat: idle_chat)
        get admin_inspector_chats_path, params: { q: { parent_chat_id_null: "1" } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Idle Chat")
      end

      it "filters children_only chats" do
        child = create(:chat, title: "Child Chat", parent_chat: idle_chat)
        get admin_inspector_chats_path, params: { q: { parent_chat_id_not_null: "1" } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Child Chat")
        expect(response.body).to include(child.id.to_s)
      end

      it "filters by operation" do
        other_op = create(:operation, name: "Ops Beta")
        other_agent = create(:agent, name: "Beta Agent", operation: other_op)
        create(:chat, agent: other_agent, model: model_record, title: "Beta Chat")
        get admin_inspector_chats_path, params: { operation: other_op.slug }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Beta Chat")
        expect(response.body).not_to include("Idle Chat")
      end
    end
  end

  describe "GET /inspector/chats/:id" do
    let(:chat) { create(:chat, agent:, model: model_record, title: "Debug Chat") }

    it "returns a successful response" do
      get admin_inspector_chat_path(chat)
      expect(response).to have_http_status(:ok)
    end

    it "displays the chat title" do
      get admin_inspector_chat_path(chat)
      expect(response.body).to include("Debug Chat")
    end

    it "displays the chat ID" do
      get admin_inspector_chat_path(chat)
      expect(response.body).to include(chat.id.to_s)
    end

    it "displays the agent name" do
      get admin_inspector_chat_path(chat)
      expect(response.body).to include(agent.name)
    end

    it "displays the model ID" do
      get admin_inspector_chat_path(chat)
      expect(response.body).to include("gpt-4.1")
    end

    it "displays the chat status" do
      get admin_inspector_chat_path(chat)
      expect(response.body).to include("idle")
    end

    it "does not show the list link in the header" do
      get admin_inspector_chat_path(chat)
      expect(response.body).not_to include("All Chats")
    end

    it "does not show the playground link for non-user chats" do
      get admin_inspector_chat_path(chat)
      expect(response.body).not_to include("Open in playground")
    end

    it "shows the playground link for user chats" do
      chat.update!(execution_context: :user)
      get admin_inspector_chat_path(chat)
      expect(response.body).to include("Open in playground")
    end

    context "with messages" do
      before do
        create(:message, :user, chat:, content: "Hello inspector")
        create(:message, :assistant, chat:, content: "I am the assistant", model: model_record,
                                     input_tokens: 150, output_tokens: 25, cached_tokens: 10,
                                     duration_ms: 1234,)
      end

      it "displays all messages" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("Hello inspector")
        expect(response.body).to include("I am the assistant")
      end

      it "shows message count" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("Messages (2)")
      end

      it "shows token information" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("150")
        expect(response.body).to include("25")
      end

      it "shows duration information" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("1.23s")
      end

      it "renders parsed reference messages without exposing the hidden marker" do
        create(:message, :user, chat:, content: referenced_message_content)

        get admin_inspector_chat_path(chat)

        expect(response.body).to include("Update #echo-test")
        expect(response.body).to include("Echo Test")
        expect(response.body).not_to include("<!-- chat_references:")
      end
    end

    context "with tool calls" do
      let(:assistant_message) { create(:message, :assistant, chat:, content: "Let me query that") }

      before do
        create(:tool_call, message: assistant_message, name: "sql_query_test",
                           arguments: { "question" => "How many users?" },
                           duration_ms: 567,)
      end

      it "displays tool call details" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("sql_query_test")
        expect(response.body).to include("How many users?")
      end

      it "displays tool call duration" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("567ms")
      end
    end

    context "with system messages" do
      before do
        create(:message, :system, chat:, content: "You are a helpful assistant")
      end

      it "displays system messages" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("You are a helpful assistant")
      end

      it "counts system messages" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("1 system")
      end
    end

    context "with parent chat" do
      let(:parent_chat) { create(:chat, agent:, model: model_record, title: "Parent Chat") }
      let(:chat) { create(:chat, agent:, model: model_record, title: "Child Chat", parent_chat:) }

      it "displays parent chat link" do
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("Parent Chat")
        expect(response.body).to include("Back to parent")
      end
    end

    context "with child chats" do
      it "displays child chats panel" do
        create(:chat, agent:, model: model_record, title: "Child Analysis", parent_chat: chat)
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("Child Chats")
        expect(response.body).to include("Child Analysis")
      end

      it "includes aggregated totals label" do
        create(:chat, agent:, model: model_record, title: "Child Analysis", parent_chat: chat)
        get admin_inspector_chat_path(chat)
        expect(response.body).to include("incl. children")
      end

      it "displays aggregated child cost and token metrics" do
        child_chat = create(:chat, agent:, model: model_record, title: "Child Analysis", parent_chat: chat)
        create(:message, :assistant, chat: child_chat, model: model_record,
                                     content: "Priced child response", input_tokens: 100, output_tokens: 50,)
        create(:message, :assistant, chat: child_chat, content: "Unpriced child response")

        get admin_inspector_chat_path(chat)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Child Analysis")
      end
    end
  end
end
