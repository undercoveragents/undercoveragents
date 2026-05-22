# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatUiHelper do
  describe "#build_chat_component" do
    before do
      helper.define_singleton_method(:current_client) do
        {
          name: "Branded Client",
          labels: {
            "send_button_label" => "Ship",
            "attach_button_label" => "Upload",
            "stop_button_label" => "Abort",
            "drop_files_label" => "Drop branded files",
          },
          message_actions: {
            "visibility" => "always",
            "copy_assistant_response" => true,
            "copy_user_message" => false,
            "assistant_feedback" => true,
          },
          composer: {
            "thinking_level_selector_enabled" => true,
          },
        }
      end
    end

    it "builds the playground component defaults", :aggregate_failures do
      component = helper.build_chat_component(variant: :playground, agent_name: "Planner")

      expect(component).to have_attributes(
        variant: :playground,
        container_class: "playground-chat-area",
        empty_state_body: "Type a message below to begin chatting with Planner.",
        attach_label: "Attach",
        send_label: "Send",
        stop_label: "Stop",
        drop_label: "Drop files here",
      )
      expect(component.root_classes).to eq(
        "playground-chat-area shared-chat shared-chat--playground shared-chat--message-actions-hover",
      )
      expect(component.allow_attachments?).to be(true)
      expect(component.allow_drag_drop?).to be(true)
      expect(component.message_actions.visibility).to eq("hover")
      expect(component.message_actions.copy_assistant_response).to be(true)
      expect(component.message_actions.copy_user_message).to be(true)
      expect(component.message_actions.assistant_feedback).to be(true)
    end

    it "builds the application component defaults", :aggregate_failures do
      component = helper.build_chat_component(variant: :application, agent_name: "Application Agent")

      expect(component).to have_attributes(
        variant: :application,
        container_class: "ms-chat-panel",
        empty_state_title: nil,
        attach_label: "Attach",
        send_label: "Send",
        stop_label: "Stop",
        drop_label: "Drop files here",
      )
      expect(component.root_classes).to eq(
        "ms-chat-panel shared-chat shared-chat--application shared-chat--message-actions-hover",
      )
      expect(component.allow_attachments?).to be(true)
      expect(component.allow_drag_drop?).to be(false)
      expect(component.thinking_level_selector_visible?).to be(true)
      expect(component.references_enabled?).to be(false)
      expect(component.message_actions.visibility).to eq("hover")
    end

    it "hides the thinking selector when the selected model does not support reasoning" do
      model = build(:model, capabilities: ["text"])
      component = helper.build_chat_component(variant: :application).with_attachment_model(model)

      expect(component.thinking_level_selector_visible?).to be(false)
    end

    it "keeps the thinking selector available for DeepSeek tool-enabled chats" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      agent = create(:agent, operation: tenant.default_operation)
      agent.runtime_tool_keys = ["resources.list_resources"]
      chat = build(:chat, agent:)
      model = build(:model, model_id: "deepseek-v4-flash", provider: "deepseek", capabilities: ["reasoning"])

      expect(helper.chat_thinking_level_selector_supported?(chat, model_record: model)).to be(true)
    end

    it "falls back to the agent thinking effort when system preferences are unconfigured" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      agent = create(
        :agent,
        operation: tenant.default_operation,
        llm_config_source: "system_preference",
        thinking_effort: "high",
      )
      chat = build(:chat, agent:)

      SystemPreference.current(tenant:)

      expect(helper.effective_chat_thinking_effort(chat)).to eq("high")
    end

    it "applies customized control labels only to the client variant", :aggregate_failures do
      component = helper.build_chat_component(variant: :client)

      expect(component).to have_attributes(
        attach_label: "Upload",
        send_label: "Ship",
        stop_label: "Abort",
        drop_label: "Drop branded files",
      )
      expect(component.root_classes).to eq(
        "chat-container shared-chat shared-chat--client shared-chat--message-actions-always",
      )
      expect(component.message_actions.visibility).to eq("always")
      expect(component.message_actions.copy_assistant_response).to be(true)
      expect(component.message_actions.copy_user_message).to be(false)
      expect(component.message_actions.assistant_feedback).to be(true)
      expect(component.thinking_level_selector_visible?).to be(true)
      expect(component.thinking_level_options).to include(
        ["Thinking: auto", ""],
        ["Thinking: high", "high"],
      )
    end

    it "enables generic references only when configured" do
      component = helper.build_chat_component(
        variant: :application,
        references: helper.chat_reference_config(enabled: true, search_url: "/references", kinds: ["missions"]),
      )

      expect(component.references_enabled?).to be(true)
      expect(component.reference_config.kinds_value).to eq("missions")
    end

    it "disables drag and drop when attachments are disabled" do
      component = helper.build_chat_component(variant: :client, allow_attachments: false)

      expect(component.allow_attachments?).to be(false)
      expect(component.allow_drag_drop?).to be(false)
    end

    it "disables attachments when the selected model cannot accept files" do
      model = build(:model, modalities: { "input" => ["text"], "output" => ["text"] })
      component = helper.build_chat_component(variant: :client, allow_attachments: true, allow_drag_drop: true)
                        .with_attachment_model(model)

      expect(component.allow_attachments?).to be(false)
      expect(component.allow_drag_drop?).to be(false)
      expect(component.attachment_accept).to be_nil
    end

    it "disables attachments when no model metadata is available" do
      component = helper.build_chat_component(variant: :client, allow_attachments: true, allow_drag_drop: true)
                        .with_attachment_model(nil)

      expect(component.allow_attachments?).to be(false)
      expect(component.allow_drag_drop?).to be(false)
      expect(component.attachment_accept).to be_nil
    end

    it "keeps the model-derived attachment accept list when attachments are supported" do
      model = build(:model, modalities: { "input" => ["text", "image", "pdf"], "output" => ["text"] })
      component = helper.build_chat_component(variant: :client, allow_attachments: true, allow_drag_drop: true)
                        .with_attachment_model(model)

      expect(component.allow_attachments?).to be(true)
      expect(component.allow_drag_drop?).to be(true)
      expect(component.attachment_accept).to eq("image/*,application/pdf")
    end

    it "exposes message action helpers for all chat variants", :aggregate_failures do
      user = create(:user)
      chat = create(:chat, :user_context, user:)
      message = create(:message, :assistant, chat:)
      application_component = helper.build_chat_component(variant: :application)
      playground_component = helper.build_chat_component(variant: :playground)
      client_component = helper.build_chat_component(variant: :client)

      expect(application_component.message_actions.enabled_for?("tool")).to be(false)
      expect(helper.chat_message_feedback_path(chat:, message:, component: application_component))
        .to eq(message_feedback_admin_agent_alpha_path(message_id: message.id))
      expect(helper.chat_message_feedback_path(chat:, message:, component: playground_component))
        .to eq(message_feedback_admin_playground_chat_path(chat, message_id: message.id))
      expect(helper.chat_message_feedback_path(chat:, message:, component: client_component))
        .to eq(message_feedback_chat_path(chat, message_id: message.id))
      expect(helper.chat_message_feedback_categories).to eq(MessageFeedback::NEGATIVE_CATEGORIES)
      expect(helper.chat_message_copy_text(message)).to eq(message.display_content.to_s)
      expect(helper.chat_message_actions_ui_context_selector(application_component))
        .to eq("#admin-agent-alpha-page-context")
    end

    it "adds preview params to client message action paths for admin preview surfaces" do
      user = create(:user)
      channel = create(:channel, :client, tenant: user.tenant)
      chat = create(:chat, :user_context, user:, channel:)
      message = create(:message, :assistant, chat:)

      helper.define_singleton_method(:admin_client_preview?) { true }
      helper.define_singleton_method(:current_client_record) { channel }
      allow(helper).to receive(:client_chat_preview_params)
        .with(client: channel)
        .and_return(view: "preview", chat_id: chat.id)

      expect(helper.send(:chat_message_action_path_options, chat:, message:)).to eq(
        message_id: message.id,
        view: "preview",
        chat_id: chat.id,
      )
    end

    it "falls back to a generic agent label when the playground agent name is blank" do
      component = helper.build_chat_component(variant: :playground, agent_name: "")

      expect(component.empty_state_body).to eq("Type a message below to begin chatting with the agent.")
    end

    it "honors explicit playground drag and drop settings" do
      component = helper.build_chat_component(
        variant: :playground,
        agent_name: "Planner",
        allow_attachments: true,
        allow_drag_drop: false,
      )

      expect(component.allow_drag_drop?).to be(false)
    end

    it "falls back to a generic agent label when the application agent name is blank" do
      component = helper.build_chat_component(variant: :application, agent_name: "")

      expect(component.placeholder).to eq("Ask to Agent Alpha… (type # to reference something)")
    end

    it "raises for an unknown variant" do
      expect { helper.build_chat_component(variant: :unknown) }
        .to raise_error(ArgumentError, "Unknown chat component variant: unknown")
    end
  end

  describe "#chat_input_data" do
    it "returns the shared textarea bindings" do
      data = helper.chat_input_data

      expect(data[:chat_target]).to eq("input")
      expect(data[:action]).to include("input->chat#resizeInput")
      expect(data[:action]).to include("keydown->chat#handleKeydown")
    end

    it "adds reference picker bindings when the component opts in" do
      component = helper.build_chat_component(
        variant: :application,
        references: helper.chat_reference_config(enabled: true, search_url: "/references", kinds: ["missions"]),
      )
      data = helper.chat_input_data(component)

      expect(data[:chat_references_target]).to eq("input")
      expect(data[:action]).to include("input->chat-references#input")
      expect(data[:action]).to include("keydown->chat-references#keydown")
    end
  end

  describe "#chat_shell_root_data" do
    let(:chat) { build_stubbed(:chat, id: 42) }

    it "returns the base controller data when drag and drop is disabled" do
      component = helper.build_chat_component(variant: :application)
      data = helper.chat_shell_root_data(chat, "/cancel", "/poll", component)

      expect(data).to eq(
        controller: "chat",
        chat_chat_id_value: 42,
        chat_cancel_url_value: "/cancel",
        chat_poll_url_value: "/poll",
        action: "human-in-the-loop-tool-call:submitted->chat#submitHumanInTheLoopAnswers " \
                "human-in-the-loop-tool-call:failed->chat#rollbackHumanInTheLoopAnswers",
      )
    end

    it "adds reference controller data only for opted-in components" do
      component = helper.build_chat_component(
        variant: :application,
        references: helper.chat_reference_config(enabled: true, search_url: "/references", kinds: ["missions"]),
      )
      data = helper.chat_shell_root_data(chat, "/cancel", "/poll", component)

      expect(data[:controller]).to eq("chat chat-references")
      expect(data[:chat_references_url_value]).to eq("/references")
      expect(data[:chat_references_trigger_value]).to eq("#")
      expect(data[:chat_references_kinds_value]).to eq("missions")
    end

    it "mounts the chat stream controller for direct chat shells" do
      component = helper.build_chat_component(variant: :client)
      data = helper.chat_shell_root_data(chat, "/cancel", "/poll", component)

      expect(data[:controller]).to eq("chat chat-stream")
      expect(data[:chat_stream_stream_token_value]).to eq(chat.signed_ui_stream_name)
    end

    it "adds drop zone bindings when drag and drop is enabled", :aggregate_failures do
      model = build(:model, modalities: { "input" => ["image"], "output" => ["text"] })
      component = helper.build_chat_component(variant: :client, allow_drag_drop: true).with_attachment_model(model)
      data = helper.chat_shell_root_data(chat, "/cancel", "/poll", component)

      expect(data[:chat_target]).to eq("dropZone")
      expect(data[:action]).to include("dragenter->chat#dragEnter")
      expect(data[:action]).to include("dragover->chat#dragOver")
      expect(data[:action]).to include("dragleave->chat#dragLeave")
      expect(data[:action]).to include("drop->chat#drop")
      expect(data[:chat_attachment_accept_value]).to eq("image/*")
    end

    it "keeps the HITL submit binding when drag and drop is enabled" do
      model = build(:model, modalities: { "input" => ["image"], "output" => ["text"] })
      component = helper.build_chat_component(variant: :client, allow_drag_drop: true).with_attachment_model(model)
      data = helper.chat_shell_root_data(chat, "/cancel", "/poll", component)

      expect(data[:action]).to include(
        "human-in-the-loop-tool-call:submitted->chat#submitHumanInTheLoopAnswers",
      )
      expect(data[:action]).to include(
        "human-in-the-loop-tool-call:failed->chat#rollbackHumanInTheLoopAnswers",
      )
    end
  end

  describe "generic chat helpers" do
    let(:overlapping_reference_payloads) do
      [
        {
          "type" => "Mission",
          "label" => "Launch",
          "mention" => "#launch",
          "display_mention" => "#launch",
          "prompt_text" => "mission id: 23",
        },
        {
          "type" => "Mission",
          "label" => "Launch Plan",
          "mention" => "#launch-plan",
          "display_mention" => "#launch-plan",
          "prompt_text" => "mission id: 24",
        },
      ]
    end

    it "truncates chat titles for sidebar display" do
      chat = build(:chat, title: "A" * 50)

      result = helper.chat_display_title(chat)

      expect(result.length).to be <= 40
      expect(result).to end_with("...")
    end

    it "formats message times" do
      message = build(:message, created_at: Time.zone.parse("2026-01-15 14:30:00"))

      expect(helper.chat_message_time(message)).to match(/02:30 PM/)
    end

    it "detects the active chat" do
      chat = build_stubbed(:chat)
      other = build_stubbed(:chat)

      expect(helper.chat_active?(chat, chat)).to be(true)
      expect(helper.chat_active?(chat, other)).to be(false)
      expect(helper.chat_active?(chat, nil)).to be(false)
    end

    it "returns status icons for chat states" do
      expect(helper.chat_status_icon("streaming")).to include("fa-spin")
      expect(helper.chat_status_icon("cancelled")).to include("fa-ban")
      expect(helper.chat_status_icon("idle")).to include("fa-circle")
    end

    it "returns role labels for chat messages" do
      expect(helper.chat_role_label("user")).to eq("You")
      expect(helper.chat_role_label("assistant")).to eq("Assistant")
      expect(helper.chat_role_label("system")).to eq("System")
    end

    it "returns display content and references for chat messages" do
      content = ChatReferences::MessagePayload.pack(
        content: "Update #launch-plan",
        references: [
          {
            "type" => "Mission",
            "label" => "Launch Plan",
            "mention" => "#launch-plan",
            "display_mention" => "#launch-plan",
            "prompt_text" => "mission id: 23",
          },
        ],
      )
      message = build(:message, :user, content:)

      expect(helper.chat_message_display_content(message)).to eq("Update #launch-plan")
      expect(helper.chat_message_references(message)).to contain_exactly(hash_including("mention" => "#launch-plan"))
      expect(helper.chat_message_context_references(message)).to eq([])
    end

    it "renders inline reference badges with the record label" do
      content = ChatReferences::MessagePayload.pack(
        content: "Update #launch-plan",
        references: [
          {
            "type" => "Mission",
            "label" => "Launch Plan",
            "mention" => "#launch-plan",
            "display_mention" => "#launch-plan",
            "prompt_text" => "mission id: 23",
          },
        ],
      )
      message = build(:message, :user, content:)
      html = helper.chat_message_display_html(message)

      expect(html).to include("shared-chat__inline-reference")
      expect(html).to include("Launch Plan")
      expect(html).not_to include(">#launch-plan<")
    end

    it "renders longer inline reference badges before prefix matches" do
      content = ChatReferences::MessagePayload.pack(
        content: "Compare #launch and #launch-plan",
        references: overlapping_reference_payloads,
      )
      message = build(:message, :user, content:)
      html = helper.chat_message_display_html(message)

      expect(html.scan("shared-chat__inline-reference").count).to eq(2)
      expect(html).to include("Launch Plan")
      expect(html).to include("Launch")
      expect(html).not_to include("</code>-plan")
    end

    it "returns context reference badges for references outside the content" do
      content = ChatReferences::MessagePayload.pack(
        content: "Is it valid?",
        references: [{ "display_mention" => "#launch-plan", "prompt_text" => "mission id: 23" }],
      )
      message = build(:message, :user, content:)

      expect(helper.chat_message_context_references(message)).to contain_exactly(
        hash_including("display_mention" => "#launch-plan"),
      )
    end

    it "falls back to a generic reference badge label" do
      expect(helper.chat_reference_badge_text({})).to eq("Reference")
    end

    it "prefers the record label for reference badge text" do
      expect(
        helper.chat_reference_badge_text({ "label" => "Launch Plan", "display_mention" => "#launch-plan" }),
      ).to eq("Launch Plan")
    end

    it "includes id and slug metadata in reference badge titles when available" do
      expect(
        helper.chat_reference_badge_title(
          { "type" => "Mission", "label" => "Launch Plan", "id" => 23, "slug" => "launch-plan" },
        ),
      ).to eq("Mission · Launch Plan · id: 23 · slug: launch-plan")
    end

    it "returns image and document icons for attachments" do
      expect(helper.chat_attachment_icon(double(content_type: "image/png"))).to eq("fa-file-image")
      expect(helper.chat_attachment_icon(double(content_type: "application/pdf"))).to eq("fa-file-pdf")
      expect(helper.chat_attachment_icon(double(content_type: "text/plain"))).to eq("fa-file-lines")
    end

    it "returns media and generic icons for attachments" do
      expect(helper.chat_attachment_icon(double(content_type: "audio/mpeg"))).to eq("fa-file-audio")
      expect(helper.chat_attachment_icon(double(content_type: "video/mp4"))).to eq("fa-file-video")
      expect(helper.chat_attachment_icon(double(content_type: "application/octet-stream"))).to eq("fa-file")
    end
  end
end
