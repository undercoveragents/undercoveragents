# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AgentAlphas", :unauthenticated do
  let(:user) { create(:user, :admin, tenant: default_tenant) }

  def response_document
    response.parsed_body
  end

  def agent_alpha_mount
    response_document.at_css("#admin-agent-alpha")
  end

  def agent_alpha_frame
    response_document.at_css("turbo-frame#admin-agent-alpha-frame")
  end

  def agent_alpha_frame_state
    response_document.at_css("[data-chat-stream-frame-state]")
  end

  def agent_alpha_sidebar_header
    response_document.at_css(".ms-sidebar-panel[data-sidebar-tab='assistant'] .ms-sidebar-panel-header")
  end

  def expect_agent_alpha_mount_shell
    expect(agent_alpha_mount).to be_present
    expect(agent_alpha_mount.attribute("data-turbo-permanent")).to be_nil
  end

  def expect_persistent_agent_alpha_frame
    expect(agent_alpha_frame).to be_present
    expect(agent_alpha_frame.attribute("data-turbo-permanent")).to be_present
    expect(agent_alpha_frame["data-controller"]).to eq("persistent-lazy-frame")
    expect(agent_alpha_frame["src"]).to eq(admin_agent_alpha_path)
  end

  def expect_persistent_agent_alpha_frame_response
    expect(agent_alpha_frame).to be_present
    expect(agent_alpha_frame.attribute("data-turbo-permanent")).to be_present
  end

  def expect_content_frame_targets(nodes)
    expect(nodes).not_to be_empty
    nodes.each do |node|
      expect(node["data-turbo-frame"]).to eq("app-content-frame")
    end
  end

  def expect_persistent_agent_alpha_mount
    expect_agent_alpha_mount_shell
    expect_persistent_agent_alpha_frame
  end

  def expect_persistent_agent_alpha_stream_source
    expect(response.body).to include('id="chat-stream-source"')
    expect(response.body).to include('data-controller="chat-stream"')
    expect(response.body).to include("data-chat-stream-stream-token-value")
    expect(response.body).not_to include("turbo-cable-stream-source")
  end

  def expect_agent_alpha_sidebar_branding
    expect(response.body).to include("fa-brain")
    expect(response.body).to include("Agent Alpha")
  end

  def expect_agent_alpha_sidebar_header
    header = agent_alpha_sidebar_header

    expect(header).to be_present
    expect(header.at_css(".ms-sidebar-panel-header-title")).to be_present
    expect(header.at_css(".ms-sidebar-panel-close")).to be_nil

    header
  end

  def expect_agent_alpha_sidebar_controls
    header = expect_agent_alpha_sidebar_header

    history_button = header.at_css(".ms-sidebar-panel-header-actions .btn.btn-secondary.btn-sm[title='Chat history']")
    new_button = header.at_css(".ms-sidebar-panel-header-actions .btn.btn-secondary.btn-sm[title='New chat']")

    expect(history_button).to be_present
    expect(history_button.text).to include("Chats")
    expect(new_button).to be_present
    expect(new_button.text).to include("New Chat")
    expect(new_button["href"]).to eq(admin_agent_alpha_path(new: 1))
    expect_agent_alpha_sidebar_branding
  end

  def expect_agent_alpha_sidebar_without_chat_controls
    header = expect_agent_alpha_sidebar_header

    expect(header.css(".btn[title='Chat history'], .btn[title='New chat']")).to be_empty
    expect_agent_alpha_sidebar_branding
  end

  def expect_agent_alpha_composer_form
    [
      "admin-agent-alpha-frame",
      "shared-chat__composer",
      'name="message[chat_id]"',
      'name="message[ui_context_token]"',
      'name="message[references]"',
      'data-controller="chat chat-references"',
      'data-chat-references-url-value="/admin/agent_alpha/references"',
      'data-chat-references-target="searchInput"',
      "shared-chat__control-button--reference",
    ].each do |fragment|
      expect(response.body).to include(fragment)
    end
  end

  before do
    create(:model, model_id: "gpt-4.1", provider: "openai", capabilities: ["text", "reasoning"])
    create(:system_preference, :configured)
    sign_in(user)
  end

  describe "GET /admin" do
    it "renders the shared admin sidebar with the assistant tab" do
      get admin_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="panel-sidebar"')
      expect(response.body).to include('data-sidebar-tab="assistant"')
    end

    it "renders the persistent application agent mount and assistant controls" do
      get admin_root_path

      expect(response).to have_http_status(:ok)
      expect_persistent_agent_alpha_mount
      expect_persistent_agent_alpha_stream_source
      expect_agent_alpha_sidebar_controls
    end

    it "routes admin shell navigation through the content frame" do
      get admin_root_path

      admin_shell_links = response_document.css(".sidebar a[href^='/admin']")
      operation_switch_forms = response_document.css(".sidebar form[action*='/switch']")

      expect_content_frame_targets(admin_shell_links)
      expect_content_frame_targets(operation_switch_forms)
    end
  end

  describe "GET /admin/agent_alpha" do
    it "returns a successful response" do
      get admin_agent_alpha_path

      expect(response).to have_http_status(:ok)
    end

    it "renders the chat composer form inside the shared sidebar frame" do
      get admin_agent_alpha_path

      expect_persistent_agent_alpha_frame_response
      expect_agent_alpha_composer_form
    end

    it "shows the thinking selector when the Agent Alpha model supports reasoning" do
      get admin_agent_alpha_path

      expect(response.body).to include('name="message[thinking_effort]"')
    end

    it "labels the thinking selector with the current default effort" do
      SystemPreference.current(tenant: user.tenant).update!(thinking_effort: "low")

      get admin_agent_alpha_path

      selector = response_document.at_css(".shared-chat__thinking-level-select")
      options = selector.css("option").map { |option| [option.text, option["value"]] }

      expect(options.first).to eq(["Thinking: low", ""])
      expect(options).to include(["Thinking: off", "none"], ["Thinking: high", "high"])
      expect(options).not_to include(["Thinking: low", "low"])
    end

    it "hides the thinking selector when the Agent Alpha model does not support reasoning" do
      Model.find_by!(model_id: "gpt-4.1").update!(capabilities: ["text"])

      get admin_agent_alpha_path

      expect(response.body).not_to include('name="message[thinking_effort]"')
    end

    it "shows attachment controls when the Agent Alpha model accepts attachments" do
      Model.find_by!(model_id: "gpt-4.1").update!(
        modalities: { "input" => ["text", "image"], "output" => ["text"] },
      )

      get admin_agent_alpha_path

      expect(response.body).to include("shared-chat__control-button--attach")
      expect(response.body).to include('data-chat-target="fileInput"')
      expect(response.body).to include('accept="image/*"')
    end

    it "does not mount a Turbo stream source for the application panel" do
      get admin_agent_alpha_path

      expect(response.body).not_to include("turbo-cable-stream-source")
    end

    it "creates an application chat on first load" do
      expect { get admin_agent_alpha_path }
        .to change { Chat.application.for_user(user).count }.by(1)

      expect(Chat.application.for_user(user).last.agent.builtin_key).to eq("agent_alpha")
      expect(Chat.application.for_user(user).last.title).to start_with("Agent Alpha —")
    end

    it "reuses the existing application chat" do
      get admin_agent_alpha_path

      expect { get admin_agent_alpha_path }
        .not_to(change { Chat.application.for_user(user).count })
    end

    it "reopens the previously selected chat instead of falling back to the newest chat" do
      agent = BuiltinAgents::Resolver.find!("agent_alpha", tenant: user.tenant)
      selected_chat = create(
        :chat,
        :application_context,
        user:,
        agent:,
        title: "Agent Alpha — Selected",
      )
      newer_chat = create(
        :chat,
        :application_context,
        user:,
        agent:,
        title: "Agent Alpha — Newest",
      )

      get admin_agent_alpha_path(chat_id: selected_chat.id)
      get admin_agent_alpha_path

      response_chat_id = response_document.at_css('input[name="message[chat_id]"]')["value"]

      expect(response_chat_id).to eq(selected_chat.id.to_s)
      expect(response_chat_id).not_to eq(newer_chat.id.to_s)
    end

    it "renders selected chat header state inside the frame content" do
      agent = BuiltinAgents::Resolver.find!("agent_alpha", tenant: user.tenant)
      selected_chat = create(
        :chat,
        :application_context,
        user:,
        agent:,
        title: "Agent Alpha — Selected",
      )

      get admin_agent_alpha_path(chat_id: selected_chat.id)

      expect(agent_alpha_frame_state).to be_present
      expect(agent_alpha_frame_state["data-chat-stream-frame-location"]).to eq(
        admin_agent_alpha_path(chat_id: selected_chat.id),
      )
      expect(agent_alpha_frame_state["data-chat-stream-header-title"]).to eq(selected_chat.display_title_for_ui)
      expect(agent_alpha_frame_state["data-chat-stream-header-target-id"]).to eq(selected_chat.title_dom_id)
    end

    it "falls back to the newest available chat when the remembered chat was deleted" do
      agent = BuiltinAgents::Resolver.find!("agent_alpha", tenant: user.tenant)
      selected_chat = create(
        :chat,
        :application_context,
        user:,
        agent:,
        title: "Agent Alpha — Selected",
      )
      fallback_chat = create(
        :chat,
        :application_context,
        user:,
        agent:,
        title: "Agent Alpha — Fallback",
      )

      get admin_agent_alpha_path(chat_id: selected_chat.id)
      selected_chat.destroy!

      get admin_agent_alpha_path

      response_chat_id = response_document.at_css('input[name="message[chat_id]"]')["value"]

      expect(response_chat_id).to eq(fallback_chat.id.to_s)
    end

    it "falls back to a valid application chat when the requested chat_id is stale" do
      agent = BuiltinAgents::Resolver.find!("agent_alpha", tenant: user.tenant)
      fallback_chat = create(
        :chat,
        :application_context,
        user:,
        agent:,
        title: "Agent Alpha — Fallback",
      )

      get admin_agent_alpha_path(chat_id: fallback_chat.id)
      fallback_chat.destroy!

      expect { get admin_agent_alpha_path(chat_id: fallback_chat.id) }
        .to change { Chat.application.for_user(user).count }.by(1)

      response_chat_id = response_document.at_css('input[name="message[chat_id]"]')["value"]

      expect(response).to have_http_status(:ok)
      expect(response_chat_id).not_to eq(fallback_chat.id.to_s)
    end

    it "returns turbo-stream catch-up updates" do
      get admin_agent_alpha_path
      chat = Chat.application.for_user(user).last

      get admin_agent_alpha_path(chat_id: chat.id, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="update"')
      expect(response.body).to include("target=\"chat-#{chat.id}-messages\"")
      expect(response.body).to include("chat-#{chat.id}-status")
    end

    it "returns only the status target in turbo-stream catch-up while streaming" do
      get admin_agent_alpha_path
      chat = Chat.application.for_user(user).last
      create(:message, chat:, role: :assistant, content: "Partial streamed answer")
      chat.streaming!

      get admin_agent_alpha_path(chat_id: chat.id, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("chat-#{chat.id}-status")
      expect(response.body).not_to include('target="messages"')
      expect(response.body).not_to include("Partial streamed answer")
    end

    it "creates a new chat when requested" do
      get admin_agent_alpha_path
      first_chat = Chat.application.for_user(user).last

      get admin_agent_alpha_path(new: 1)

      expect(response).to have_http_status(:ok)
      expect(Chat.application.for_user(user).last.id).not_to eq(first_chat.id)
    end

    it "renders chat history" do
      get admin_agent_alpha_path
      agent = Chat.application.for_user(user).last.agent
      first = create(:chat, :application_context, user:, agent:, title: "Agent Alpha — Older")
      second = create(:chat, :application_context, user:, agent:, title: "Agent Alpha — Newer")

      get admin_agent_alpha_path(history: 1)

      history_links = response_document.css(".ms-chat-history-view-item").pluck("href")

      expect(response).to have_http_status(:ok)
      expect_persistent_agent_alpha_frame_response
      expect(response.body).to include("ms-chat-history-view")
      expect(history_links).to include(admin_agent_alpha_path(chat_id: first.id))
      expect(history_links).to include(admin_agent_alpha_path(chat_id: second.id))
    end

    context "when the default LLM is not configured" do
      before do
        SystemPreference.where(tenant: user.tenant).delete_all
      end

      it "renders an unconfigured state instead of creating a chat" do
        expect { get admin_agent_alpha_path }
          .not_to(change { Chat.application.for_user(user).count })

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(
          "Agent Alpha is unavailable until the default LLM connector and model are configured.",
        )
        expect(response.body).to include("Set it up in Preferences.")
        expect(response.body).not_to include("shared-chat__composer")
      end

      it "routes the unavailable-state preferences link through the content frame" do
        get admin_agent_alpha_path

        preferences_link = response_document.at_css("#admin-agent-alpha-frame a[href='#{admin_preferences_path}']")

        expect(preferences_link).to be_present
        expect(preferences_link["data-turbo-frame"]).to eq("app-content-frame")
      end

      it "renders the sidebar without chat controls" do
        get admin_root_path

        expect(response).to have_http_status(:ok)
        expect_agent_alpha_sidebar_without_chat_controls
      end

      it "renders a non-persistent unavailable frame so the sidebar can recover after preferences are configured" do
        get admin_root_path

        expect(agent_alpha_frame).to be_present
        expect(agent_alpha_frame.attribute("data-turbo-permanent")).to be_nil
        expect(agent_alpha_frame["src"]).to be_nil
        expect(response.body).to include(
          "Agent Alpha is unavailable until the default LLM connector and model are configured.",
        )
      end
    end
  end

  describe "POST /admin/agent_alpha/cancel" do
    it "cancels the existing application chat" do
      get admin_agent_alpha_path
      chat = Chat.application.for_user(user).last
      chat.streaming!

      post cancel_admin_agent_alpha_path, params: { chat_id: chat.id }

      expect(response).to have_http_status(:ok)
      expect(chat.reload).to be_cancelled
    end

    it "returns ok when no application chat exists yet" do
      post cancel_admin_agent_alpha_path

      expect(response).to have_http_status(:ok)
    end
  end
end
