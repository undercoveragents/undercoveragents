# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chats" do
  let(:user) { User.find_by(role: "admin") }
  let(:tenant) { user.tenant.tap(&:ensure_core_resources!) }

  def create_client_channel(agent:, default: true, name: "Support Channel")
    create(:channel, :client, tenant:, name:, default:).tap do |channel|
      create(:channel_target, channel:, target: agent, default: true)
    end
  end

  def create_channel_chat(user:, agent:, channel:)
    create(
      :chat,
      :user_context,
      user:,
      agent:,
      channel:,
      channel_target: channel.default_target,
    )
  end

  before do
    tenant
    # Ensure a Model record exists so Chat#build_chat doesn't raise RubyLLM configuration errors.
    create(:model, model_id: "gpt-4.1", provider: "openai")
  end

  describe "GET /chat" do
    context "when there are no enabled agents" do
      it "renders the shared empty state" do
        get chats_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("shared-chat shared-chat--client")
        expect(response.body).to include("shared-chat__empty-state")
        expect(response.body).to include("No agent is available yet. Please contact your administrator.")
      end
    end

    context "when an enabled agent exists but no client channel is published" do
      let(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }

      it "renders the shared empty state" do
        get chats_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("shared-chat__empty-state")
      end
    end

    context "when a default client channel exists" do
      let!(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }
      let!(:client_channel) { create_client_channel(agent:) }

      it "redirects to the most recent chat when one exists" do
        chat = create_channel_chat(user:, agent:, channel: client_channel)
        get chats_path
        expect(response).to redirect_to(chat_path(chat))
      end

      it "creates a new chat and redirects when no existing chats" do
        expect { get chats_path }.to change(Chat, :count).by(1)
        expect(response).to redirect_to(chat_path(Chat.last))
        expect(Chat.last.agent).to eq(agent)
        expect(Chat.last.channel).to eq(client_channel)
      end

      it "redirects admin preview requests to the admin channel preview page" do
        get chats_path(preview_channel_id: client_channel.to_param, admin_preview: true)

        expect(response).to redirect_to(admin_channel_path(client_channel, view: :preview))
      end
    end
  end

  describe "GET /chat/:id" do
    let(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }
    let!(:client_channel) { create_client_channel(agent:) }
    let(:chat) { create_channel_chat(user:, agent:, channel: client_channel) }

    def create_grouped_mission_tool_history(chat, trailing_duration_ms: nil)
      chat.update!(status: "streaming")
      first_message = create(:message, chat:, role: :assistant, content: nil)
      second_message = create(:message, chat:, role: :assistant, content: nil)
      create(
        :tool_call,
        message: first_message,
        name: "read_mission_flow",
        display_name: nil,
        icon: nil,
        duration_ms: 180,
      )
      create(
        :tool_call,
        message: second_message,
        name: "manage_edges",
        display_name: nil,
        icon: nil,
        duration_ms: trailing_duration_ms,
      )
    end

    def response_document
      response.parsed_body
    end

    def effective_attachment_model(chat)
      Model.find_by(model_id: chat.agent&.resolved_model_id) || chat.model
    end

    it "returns a successful response" do
      get chat_path(chat)
      expect(response).to have_http_status(:ok)
    end

    it "renders the shared chat shell" do
      get chat_path(chat)

      expect(response.body).to include("shared-chat__composer")
      expect(response.body).to include("shared-chat__messages")
    end

    it "renders the thinking level selector when the client channel enables it" do
      client_channel.update!(
        configuration: client_channel.configuration.merge("thinking_level_selector_enabled" => true),
      )
      effective_attachment_model(chat).update!(capabilities: ["text", "reasoning"])

      get chat_path(chat)

      document = response_document
      selector = document.at_css(".shared-chat__thinking-level-select")

      expect(selector).to be_present
      expect(selector.css("option").map { |option| [option.text, option["value"]] }).to include(
        ["Model default", ""],
        ["High", "high"],
      )
    end

    it "hides the thinking level selector by default" do
      get chat_path(chat)

      expect(response_document.at_css(".shared-chat__thinking-level-select")).to be_nil
    end

    it "renders one assistant action row for the last assistant entry in a turn", :aggregate_failures do
      client_channel.update!(
        configuration: client_channel.configuration.to_h.merge(
          "message_actions_visibility" => "always",
          "copy_assistant_response_enabled" => true,
          "copy_user_message_enabled" => false,
          "assistant_feedback_enabled" => true,
        ),
      )
      create(:message, :user, chat:, content: "Explain the changes")
      create(:message, :assistant, chat:, content: "First step")
      tool_message = create(:message, :assistant, chat:, content: nil)
      create(:tool_call, message: tool_message, name: "read_mission_flow", duration_ms: 180)
      create(:message, :assistant, chat:, content: "Final step")

      get chat_path(chat)

      document = response_document
      assistant_actions = document.css(".shared-chat__message-actions")
      copy_button = document.at_css('button[aria-label="Copy response"]')

      expect(assistant_actions.size).to eq(1)
      expect(document.css('button[aria-label="Try again"]').size).to eq(0)
      expect(document.css('button[aria-label="Thumbs up"]').size).to eq(1)
      expect(document.css('button[aria-label="Thumbs down"]').size).to eq(1)
      expect(copy_button["data-clipboard-text-value"]).to include("First step")
      expect(copy_button["data-clipboard-text-value"]).to include("Read Mission Flow")
      expect(copy_button["data-clipboard-text-value"]).to include("Final step")
    end

    it "keeps the idle status target collapsed" do
      get chat_path(chat)

      status_shell = response_document.at_css("#chat-#{chat.id}-status")

      expect(status_shell).to be_present
      expect(status_shell["class"]).not_to include("shared-chat__status-shell--visible")
    end

    it "hides attachment controls when the chat model does not accept attachments" do
      effective_attachment_model(chat).update!(modalities: { "input" => ["text"], "output" => ["text"] })

      get chat_path(chat)

      document = response_document
      expect(document.at_css('input[type="file"]')).to be_nil
      expect(document.at_css(".shared-chat__control-button--attach")).to be_nil
    end

    it "sets the file input accept list from the chat model attachment modalities" do
      effective_attachment_model(chat).update!(
        modalities: { "input" => ["text", "image", "pdf"], "output" => ["text"] },
      )

      get chat_path(chat)

      file_input = response_document.at_css('input[type="file"]')
      expect(file_input).to be_present
      expect(file_input["accept"]).to eq("image/*,application/pdf")
      expect(response_document.at_css(".shared-chat__control-button--attach")).to be_present
    end

    it "renders grouped mission tool calls as a compact timeline alongside assistant text" do
      assistant_message = create(:message, chat:, role: :assistant, content: "Workflow updated")
      create(:tool_call, message: assistant_message, name: "read_mission_flow", display_name: nil, icon: nil)
      create(:tool_call, message: assistant_message, name: "manage_edges", display_name: nil, icon: nil)

      get chat_path(chat)

      expect(response.body).to include("Workflow updated")
      expect(response.body).to include("Read Mission Flow")
      expect(response.body).to include("Manage Edges")
      expect(response.body).to include("shared-chat__tool-timeline-item")
    end

    it "renders persisted thinking as a collapsed disclosure" do
      create(
        :message,
        chat:,
        role: :assistant,
        content: "Final answer",
        thinking_text: "First I reasoned through the problem.",
      )

      get chat_path(chat)

      document = response_document
      thinking = document.at_css("details.shared-chat__thinking")

      expect(thinking).to be_present
      expect(thinking["open"]).to be_nil
      expect(thinking.text).to include("Thinking")
      expect(thinking.text).to include("First I reasoned through the problem.")
    end

    it "keeps grouped mission tool history compact and preserves running status on refresh", :aggregate_failures do
      create_grouped_mission_tool_history(chat)

      get chat_path(chat)

      document = response_document
      groups = document.css(".shared-chat__tool-group")
      timeline_items = document.css(".shared-chat__tool-timeline-item")

      expect(groups.size).to eq(1)
      expect(document.css(".shared-chat__tool-timeline-item.is-complete").size).to eq(1)
      expect(document.css(".shared-chat__tool-timeline-item.is-running").size).to eq(1)
      expect(timeline_items.map(&:text).join(" ")).to include("Read Mission Flow")
      expect(timeline_items.map(&:text).join(" ")).to include("Manage Edges")
      expect(response.body).not_to include("Task chain")
    end

    it "keeps the group working on refresh while the chat is still streaming", :aggregate_failures do
      create_grouped_mission_tool_history(chat, trailing_duration_ms: 220)

      get chat_path(chat)

      document = response_document
      group = document.at_css(".shared-chat__tool-group")

      expect(group["class"]).to include("streaming")
      expect(document.css(".shared-chat__tool-timeline-item.is-complete").size).to eq(2)
      expect(document.css(".shared-chat__tool-timeline-item.is-running")).to be_empty
    end

    it "returns not found for another user's chat" do
      other_user = create(:user)
      other_chat = create_channel_chat(user: other_user, agent:, channel: client_channel)
      get chat_path(other_chat)
      expect(response).to have_http_status(:not_found)
    end

    it "returns not found for a chat belonging to another client channel" do
      other_agent = create(:agent, operation: tenant.default_operation, enabled: true)
      other_channel = create_client_channel(agent: other_agent, default: false, name: "Other Channel")
      other_client_chat = create_channel_chat(user:, agent: other_agent, channel: other_channel)

      get chat_path(other_client_chat)

      expect(response).to have_http_status(:not_found)
    end

    it "returns turbo-stream catch-up updates" do
      get chat_path(chat, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="update"')
      expect(response.body).to include("target=\"chat-#{chat.id}-messages\"")
      expect(response.body).to include("chat-#{chat.id}-status")
    end

    it "redirects admin preview show requests back to the admin channel preview page" do
      preview_chat = create_channel_chat(user:, agent:, channel: client_channel)

      get chat_path(preview_chat, preview_channel_id: client_channel.to_param, admin_preview: true)

      expect(response).to redirect_to(admin_channel_path(client_channel, view: :preview, chat_id: preview_chat.id))
    end
  end

  describe "POST /chat" do
    let!(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }
    let!(:client_channel) { create_client_channel(agent:) }

    it "creates a new chat and redirects to it" do
      expect { post chats_path }.to change(Chat, :count).by(1)
      expect(response).to redirect_to(chat_path(Chat.last))
    end

    it "assigns the current user to the created chat" do
      post chats_path
      expect(Chat.last.user).to eq(user)
    end

    it "sets execution_context to user" do
      post chats_path
      expect(Chat.last.execution_context).to eq("user")
    end

    it "redirects admin preview creates back to the admin channel preview page" do
      expect do
        post chats_path(preview_channel_id: client_channel.to_param, admin_preview: true)
      end.to change(Chat, :count).by(1)

      expect(response).to redirect_to(admin_channel_path(client_channel, view: :preview, chat_id: Chat.last.id))
      expect(Chat.last.channel).to eq(client_channel)
    end

    it "refreshes chat column information when a preview worker has stale chat schema metadata" do
      columns_hash_calls = 0

      allow(Chat).to receive(:columns_hash).and_wrap_original do |method, *args|
        columns_hash_calls += 1
        columns_hash_calls == 1 ? {} : method.call(*args)
      end
      allow(Chat).to receive(:reset_column_information).and_call_original

      post chats_path(preview_channel_id: client_channel.to_param, admin_preview: true)

      expect(Chat).to have_received(:reset_column_information)
      expect(response).to redirect_to(admin_channel_path(client_channel, view: :preview, chat_id: Chat.last.id))
    end
  end

  describe "DELETE /chat/:id" do
    let(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }
    let!(:client_channel) { create_client_channel(agent:) }
    let!(:chat) { create_channel_chat(user:, agent:, channel: client_channel) }

    it "destroys the chat and redirects" do
      expect { delete chat_path(chat) }.to change(Chat, :count).by(-1)
      expect(response).to redirect_to(chats_path)
    end

    it "redirects admin preview deletes back to the channel preview page" do
      preview_chat = create_channel_chat(user:, agent:, channel: client_channel)

      expect do
        delete chat_path(preview_chat, preview_channel_id: client_channel.to_param, admin_preview: true)
      end.to change(Chat, :count).by(-1)

      expect(response).to redirect_to(admin_channel_path(client_channel, view: :preview))
    end
  end

  describe "POST /chat/:id/cancel" do
    let(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }
    let!(:client_channel) { create_client_channel(agent:) }
    let!(:chat) { create_channel_chat(user:, agent:, channel: client_channel) }

    it "cancels the chat and returns ok" do
      post cancel_chat_path(chat)
      expect(response).to have_http_status(:ok)
      expect(chat.reload.status).to eq("cancelled")
    end
  end

  describe "GET /chat/more" do
    it "responds to turbo_stream format" do
      get more_chats_path, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      expect(response).to have_http_status(:ok)
    end
  end
end
