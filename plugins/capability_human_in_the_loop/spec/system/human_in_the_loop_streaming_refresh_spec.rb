# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Human in the loop streaming refresh", :js do
  let!(:tenant) do
    create(:tenant).tap(&:ensure_core_resources!)
  end
  let!(:operation) { tenant.default_operation }
  let!(:user) { create(:user, :admin, tenant:) }
  let!(:model) { create(:model, model_id: "gpt-4.1", provider: "openai") }
  let!(:connector) { create(:connector, :llm_provider, :enabled, tenant:) }
  let!(:agent) { create(:agent, operation:, llm_connector: connector, model_id: "gpt-4.1", name: "Demo Buddy") }
  let!(:chat) { create(:chat, :playground_context, agent:, user:, model:) }

  before do
    create(
      :system_preference,
      :configured,
      tenant:,
      llm_connector: connector,
      model_id: "gpt-4.1",
    )
  end

  it "replaces a completed live ask_user_questions row with the persisted widget" do
    open_playground_chat

    tool_call_id = "call_hitl_refresh"
    persist_pending_hitl_message(tool_call_id:)

    broadcast_status("streaming")
    broadcast_chunk(persisted_message_content)
    expect_streaming_prompt_visible

    broadcast_tool_event(tool_call_id:, event: "start")
    expect_streaming_tool_row_visible

    broadcast_tool_event(tool_call_id:, event: "complete")
    broadcast_status("idle")

    expect_persisted_widget_visible
  end

  it "waits for the chat stream connection before submitting answers" do
    persist_pending_hitl_message(tool_call_id: "call_hitl_submit_wait")
    open_playground_chat

    expect(page).to have_css(".shared-chat--playground .hitl-widget__title", text: "Need Your Input")

    install_submit_order_probe

    first(".shared-chat--playground .hitl-widget__choice-pill", text: "The Matrix").click
    first(".shared-chat--playground .hitl-widget__submit").click

    expect(page).to have_css(
      "body[data-hitl-submit-events='wait-start,wait-finished,fetch']",
      visible: :all,
    )
  end

  it "keeps a local resumed stream active across an idle catch-up refresh" do
    persist_pending_hitl_message(tool_call_id: "call_hitl_resume_refresh")
    open_playground_chat

    expect(page).to have_css(".shared-chat--playground .hitl-widget__title", text: "Need Your Input")

    install_resume_refresh_race_probe

    first(".shared-chat--playground .hitl-widget__choice-pill", text: "The Matrix").click
    first(".shared-chat--playground .hitl-widget__submit").click

    expect(page).to have_css("body[data-hitl-resume-control-state='stop']", visible: :all)
    expect(page).to have_css(
      ".shared-chat--playground .shared-chat__message-content",
      text: "Resumed reply visible",
    )
  end

  it "refreshes the transcript when a resumed stream ends without visible chunks" do
    persist_pending_hitl_message(tool_call_id: "call_hitl_resume_missing_chunks")
    open_playground_chat

    expect(page).to have_css(".shared-chat--playground .hitl-widget__title", text: "Need Your Input")

    install_silent_resume_probe

    first(".shared-chat--playground .hitl-widget__choice-pill", text: "The Matrix").click
    first(".shared-chat--playground .hitl-widget__submit").click

    expect(page).to have_css("body[data-hitl-silent-refresh='true']", visible: :all)
    expect(page).to have_css(
      ".shared-chat--playground .shared-chat__message-content",
      text: "Recovered final reply",
    )
  end

  it "accepts a stale idle catch-up response for a quiet resumed stream" do
    persist_pending_hitl_message(tool_call_id: "call_hitl_stale_resume_catch_up")
    open_playground_chat

    expect(page).to have_css(".shared-chat--playground .hitl-widget__title", text: "Need Your Input")

    install_stale_resume_catch_up_probe

    first(".shared-chat--playground .hitl-widget__choice-pill", text: "The Matrix").click
    first(".shared-chat--playground .hitl-widget__submit").click

    expect(page).to have_css("body[data-hitl-stale-catch-up='applied']", visible: :all)
    expect(page).to have_css(
      ".shared-chat--playground .shared-chat__message-content",
      text: "Recovered from stale fallback poll",
    )
    expect(page).to have_css(".shared-chat--playground [data-chat-target='submitButton']:not(.hidden)")
  end

  it "accepts a second stale idle catch-up response after a quiet resumed stream", :aggregate_failures do
    persist_pending_hitl_message(tool_call_id: "call_hitl_repeated_stale_resume_catch_up")
    open_playground_chat

    expect(page).to have_css(".shared-chat--playground .hitl-widget__title", text: "Need Your Input")

    install_repeated_stale_resume_catch_up_probe

    first(".shared-chat--playground .hitl-widget__choice-pill", text: "The Matrix").click
    first(".shared-chat--playground .hitl-widget__submit").click

    expect(page).to have_css("body[data-hitl-repeated-stale-catch-up-count='1']", visible: :all)
    expect(page).to have_css(
      ".shared-chat--playground .shared-chat__message-content",
      text: "Recovered from repeated stale fallback poll 1",
    )
    expect(page).to have_css(".shared-chat--playground [data-chat-target='submitButton']:not(.hidden)")

    first(".shared-chat--playground .hitl-widget__choice-pill", text: "The Matrix").click
    first(".shared-chat--playground .hitl-widget__submit").click

    expect(page).to have_css("body[data-hitl-repeated-stale-catch-up-count='2']", visible: :all)
    expect(page).to have_css(
      ".shared-chat--playground .shared-chat__message-content",
      text: "Recovered from repeated stale fallback poll 2",
    )
    expect(page).to have_css(".shared-chat--playground [data-chat-target='submitButton']:not(.hidden)")
  end

  it "rebinds the messages target before rendering resumed chunks" do
    persist_pending_hitl_message(tool_call_id: "call_hitl_rebind_messages_target")
    open_playground_chat

    expect(page).to have_css(".shared-chat--playground .hitl-widget__title", text: "Need Your Input")

    install_disconnected_messages_resume_probe

    first(".shared-chat--playground .hitl-widget__choice-pill", text: "The Matrix").click
    first(".shared-chat--playground .hitl-widget__submit").click

    expect(page).to have_css("body[data-hitl-disconnected-messages='true']", visible: :all)
    expect(page).to have_css(
      ".shared-chat--playground .shared-chat__message-content",
      text: "Live resumed reply visible",
    )
    expect(page).to have_css(".shared-chat--playground [data-chat-target='submitButton']:not(.hidden)")
  end

  def open_playground_chat
    visit tenant_login_path(tenant)
    fill_in "Email", with: user.email
    fill_in "Password", with: "Password123!"
    click_button "Sign In"
    expect(page).to have_current_path(admin_root_path, ignore_query: true)

    visit admin_playground_chat_path(chat)
  end

  def persist_pending_hitl_message(tool_call_id:)
    message = create(
      :message,
      :assistant,
      chat:,
      content: persisted_message_content,
    )

    create(
      :tool_call,
      message:,
      tool_call_id:,
      name: "ask_user_questions",
      display_name: "Ask User Questions",
      icon: "fa-solid fa-circle-question",
      arguments: pending_hitl_state.to_h,
    )
  end

  def pending_hitl_state
    Capabilities::HumanInTheLoop::ToolCallState.build(
      prompt_text: "🎬 Let's talk about your favorite movie!",
      raw_questions: [{ prompt: "What is your favorite movie?", options: movie_options }],
      capability: build(:capabilities_human_in_the_loop_standalone),
    )
  end

  def movie_options
    [
      "The Matrix",
      "Inception",
      "The Lord of the Rings",
      "Star Wars",
      "Back to the Future",
      "The Dark Knight",
    ]
  end

  def persisted_message_content
    "Sure thing! Let me ask you about your favorite movie! 🎬"
  end

  def expect_streaming_prompt_visible
    expect(page).to have_css(
      ".shared-chat--playground #streaming-message .shared-chat__message-content",
      text: "Sure thing! Let me ask you about your favorite movie!",
    )
  end

  def expect_streaming_tool_row_visible
    expect(page).to have_css(
      ".shared-chat--playground #streaming-message .shared-chat__tool-call-name",
      text: "Ask User Questions",
    )
  end

  def expect_persisted_widget_visible
    expect(page).to have_css(".shared-chat--playground .hitl-widget__title", text: "Need Your Input")
    expect(page).to have_css(
      ".shared-chat--playground .hitl-widget__question-prompt",
      text: "What is your favorite movie?",
    )
    expect(page).to have_no_css(".shared-chat--playground #streaming-message", visible: :all)
    expect(page).to have_no_css(
      ".shared-chat--playground .shared-chat__tool-call-name",
      text: "Ask User Questions",
    )
  end

  def install_submit_order_probe
    page.execute_script(submit_order_probe_script)
  end

  def install_resume_refresh_race_probe
    page.execute_script(resume_refresh_race_probe_script, chat.id, agent.name)
  end

  def install_silent_resume_probe
    page.execute_script(silent_resume_probe_script, chat.id, agent.name)
  end

  def install_stale_resume_catch_up_probe
    page.execute_script(stale_resume_catch_up_probe_script, chat.id)
  end

  def install_repeated_stale_resume_catch_up_probe
    page.execute_script(repeated_stale_resume_catch_up_probe_script, chat.id)
  end

  def install_disconnected_messages_resume_probe
    page.execute_script(disconnected_messages_resume_probe_script, chat.id, agent.name)
  end

  def submit_order_probe_script
    <<~JS
      window.__hitlSubmitEvents = []

      const recordEvent = (name) => {
        window.__hitlSubmitEvents.push(name)
        document.body.dataset.hitlSubmitEvents = window.__hitlSubmitEvents.join(",")
      }

      const panel = document.querySelector(".shared-chat--playground")
      const chatController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat")

      chatController.waitForStreamConnection = () => {
        recordEvent("wait-start")

        return new Promise((resolve) => {
          window.setTimeout(() => {
            recordEvent("wait-finished")
            resolve(true)
          }, 25)
        })
      }

      const originalFetch = window.fetch.bind(window)
      window.fetch = (...args) => {
        recordEvent("fetch")

        const widget = document.querySelector(".shared-chat--playground .hitl-widget")
        const html = widget ? widget.outerHTML : ""
        return Promise.resolve(new Response(html, { status: 200, headers: { "Content-Type": "text/html" } }))
      }

      window.__hitlOriginalFetch = originalFetch
    JS
  end

  def resume_refresh_race_probe_script
    <<~JS
      const chatId = arguments[0]
      const agentName = arguments[1]
      const panel = document.querySelector(".shared-chat--playground")
      const chatController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat")
      const streamController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat-stream")

      chatController.waitForStreamConnection = () => Promise.resolve(true)

      const originalFetch = window.fetch.bind(window)
      window.fetch = (...args) => {
        const widget = document.querySelector(".shared-chat--playground .hitl-widget")
        const messagesId = `chat-${chatId}-messages`
        const statusId = `chat-${chatId}-status`
        const messagesMarkup = document.getElementById(messagesId)?.outerHTML ||
          `<div id="${messagesId}" data-chat-target="messages"></div>`
        const idleStatusMarkup = `<div id="${statusId}" data-chat-target="status" data-status="idle"></div>`

        window.setTimeout(async () => {
          const catchUpBody = [
            `<turbo-stream action="replace" target="${messagesId}"><template>${messagesMarkup}</template></turbo-stream>`,
            `<turbo-stream action="replace" target="${statusId}"><template>${idleStatusMarkup}</template></turbo-stream>`,
          ].join("")

          await chatController.transport.renderTurboResponse(
            new Response(catchUpBody, {
              status: 200,
              headers: { "Content-Type": "text/vnd.turbo-stream.html" },
            }),
          )

          document.body.dataset.hitlResumeControlState =
            chatController.submitButtonTarget.classList.contains("hidden") ? "stop" : "send"

          streamController.received({
            chat_id: chatId,
            type: "status",
            status: "streaming",
            parent_chat_id: null,
            agent_name: agentName,
          })
          streamController.received({
            chat_id: chatId,
            type: "chunk",
            kind: "content",
            content: "Resumed reply visible",
            parent_chat_id: null,
            agent_name: agentName,
          })
          streamController.received({
            chat_id: chatId,
            type: "status",
            status: "idle",
            parent_chat_id: null,
            agent_name: agentName,
          })
        }, 25)

        const html = widget ? widget.outerHTML : ""
        return Promise.resolve(new Response(html, { status: 200, headers: { "Content-Type": "text/html" } }))
      }

      window.__hitlOriginalFetch = originalFetch
    JS
  end

  def silent_resume_probe_script
    <<~JS
      const chatId = arguments[0]
      const agentName = arguments[1]
      const panel = document.querySelector(".shared-chat--playground")
      const chatController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat")
      const streamController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat-stream")

      chatController.waitForStreamConnection = () => Promise.resolve(true)

      chatController.transport.refreshConversation = async () => {
        document.body.dataset.hitlSilentRefresh = "true"

        const messagesId = `chat-${chatId}-messages`
        const statusId = `chat-${chatId}-status`
        const messageMarkup = `
          <article class="shared-chat__message shared-chat__message--assistant shared-chat__message--stable">
            <div class="shared-chat__assistant-panel">
              <div class="shared-chat__assistant-content">
                <div class="shared-chat__bubble shared-chat__bubble--assistant">
                  <div class="shared-chat__message-content markdown-body">Recovered final reply</div>
                </div>
              </div>
            </div>
          </article>
        `.trim()

        window.Turbo.renderStreamMessage([
          `<turbo-stream action="append" target="${messagesId}"><template>${messageMarkup}</template></turbo-stream>`,
          `<turbo-stream action="replace" target="${statusId}"><template><div id="${statusId}" data-chat-target="status" data-status="idle"></div></template></turbo-stream>`,
        ].join(""))
      }

      const originalFetch = window.fetch.bind(window)
      window.fetch = (...args) => {
        const widget = document.querySelector(".shared-chat--playground .hitl-widget")

        window.setTimeout(() => {
          streamController.received({
            chat_id: chatId,
            type: "status",
            status: "idle",
            parent_chat_id: null,
            agent_name: agentName,
          })
        }, 25)

        const html = widget ? widget.outerHTML : ""
        return Promise.resolve(new Response(html, { status: 200, headers: { "Content-Type": "text/html" } }))
      }

      window.__hitlOriginalFetch = originalFetch
    JS
  end

  def stale_resume_catch_up_probe_script
    <<~JS
      const chatId = arguments[0]
      const panel = document.querySelector(".shared-chat--playground")
      const chatController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat")

      chatController.waitForStreamConnection = () => Promise.resolve(true)

      const originalFetch = window.fetch.bind(window)
      window.fetch = (...args) => {
        const widget = document.querySelector(".shared-chat--playground .hitl-widget")

        window.setTimeout(async () => {
          const messagesId = `chat-${chatId}-messages`
          const statusId = `chat-${chatId}-status`
          const messageMarkup = `
            <article class="shared-chat__message shared-chat__message--assistant shared-chat__message--stable">
              <div class="shared-chat__assistant-panel">
                <div class="shared-chat__assistant-content">
                  <div class="shared-chat__bubble shared-chat__bubble--assistant">
                    <div class="shared-chat__message-content markdown-body">Recovered from stale fallback poll</div>
                  </div>
                </div>
              </div>
            </article>
          `.trim()
          const messagesMarkup = `
            <div id="${messagesId}" class="shared-chat__messages" data-chat-target="messages">
              ${messageMarkup}
            </div>
          `.trim()
          const idleStatusMarkup = `<div id="${statusId}" data-chat-target="status" data-status="idle"></div>`
          const catchUpBody = [
            `<turbo-stream action="replace" target="${messagesId}"><template>${messagesMarkup}</template></turbo-stream>`,
            `<turbo-stream action="replace" target="${statusId}"><template>${idleStatusMarkup}</template></turbo-stream>`,
          ].join("")

          chatController.lastUpdateAt = Date.now() - 5000
          await chatController.transport.renderTurboResponse(
            new Response(catchUpBody, {
              status: 200,
              headers: { "Content-Type": "text/vnd.turbo-stream.html" },
            }),
          )
          document.body.dataset.hitlStaleCatchUp = "applied"
        }, 25)

        const html = widget ? widget.outerHTML : ""
        return Promise.resolve(new Response(html, { status: 200, headers: { "Content-Type": "text/html" } }))
      }

      window.__hitlOriginalFetch = originalFetch
    JS
  end

  def repeated_stale_resume_catch_up_probe_script
    <<~JS
      const chatId = arguments[0]
      const panel = document.querySelector(".shared-chat--playground")
      const chatController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat")
      const originalWidgetMarkup = document.querySelector(".shared-chat--playground .hitl-widget").outerHTML
      let submitCount = 0

      chatController.waitForStreamConnection = () => Promise.resolve(true)

      const originalFetch = window.fetch.bind(window)
      window.fetch = (...args) => {
        const url = String(args[0]?.url || args[0])
        if (!url.includes("/human_in_the_loop/tool_calls/")) return originalFetch(...args)

        const widget = document.querySelector(".shared-chat--playground .hitl-widget")
        submitCount += 1
        const currentSubmitCount = submitCount

        window.setTimeout(async () => {
          const messagesId = `chat-${chatId}-messages`
          const statusId = `chat-${chatId}-status`
          const messageMarkup = `
            <article class="shared-chat__message shared-chat__message--assistant shared-chat__message--stable">
              <div class="shared-chat__assistant-panel">
                <div class="shared-chat__assistant-content">
                  <div class="shared-chat__bubble shared-chat__bubble--assistant">
                    <div class="shared-chat__message-content markdown-body">
                      Recovered from repeated stale fallback poll ${currentSubmitCount}
                    </div>
                  </div>
                </div>
              </div>
            </article>
          `.trim()
          const nextWidgetMarkup = currentSubmitCount === 1 ? originalWidgetMarkup : ""
          const messagesMarkup = `
            <div id="${messagesId}" class="shared-chat__messages" data-chat-target="messages">
              ${messageMarkup}
              ${nextWidgetMarkup}
            </div>
          `.trim()
          const idleStatusMarkup = `<div id="${statusId}" data-chat-target="status" data-status="idle"></div>`
          const catchUpBody = [
            `<turbo-stream action="replace" target="${messagesId}"><template>${messagesMarkup}</template></turbo-stream>`,
            `<turbo-stream action="replace" target="${statusId}"><template>${idleStatusMarkup}</template></turbo-stream>`,
          ].join("")

          chatController.lastUpdateAt = Date.now() - 5000
          await chatController.transport.renderTurboResponse(
            new Response(catchUpBody, {
              status: 200,
              headers: { "Content-Type": "text/vnd.turbo-stream.html" },
            }),
          )
          document.body.dataset.hitlRepeatedStaleCatchUpCount = String(currentSubmitCount)
        }, 25)

        const html = widget ? widget.outerHTML : originalWidgetMarkup
        return Promise.resolve(new Response(html, { status: 200, headers: { "Content-Type": "text/html" } }))
      }

      window.__hitlOriginalFetch = originalFetch
    JS
  end

  def disconnected_messages_resume_probe_script
    <<~JS
      const chatId = arguments[0]
      const agentName = arguments[1]
      const panel = document.querySelector(".shared-chat--playground")
      const chatController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat")
      const streamController = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat-stream")

      chatController.waitForStreamConnection = () => Promise.resolve(true)

      const originalFetch = window.fetch.bind(window)
      window.fetch = (...args) => {
        const widget = document.querySelector(".shared-chat--playground .hitl-widget")

        window.setTimeout(() => {
          const staleMessages = streamController.messagesElement
          const replacementMessages = staleMessages.cloneNode(true)
          staleMessages.replaceWith(replacementMessages)
          document.body.dataset.hitlDisconnectedMessages = String(!staleMessages.isConnected)

          streamController.received({
            chat_id: chatId,
            type: "status",
            status: "streaming",
            parent_chat_id: null,
            agent_name: agentName,
          })
          streamController.received({
            chat_id: chatId,
            type: "chunk",
            kind: "content",
            content: "Live resumed reply visible",
            parent_chat_id: null,
            agent_name: agentName,
          })
          streamController.received({
            chat_id: chatId,
            type: "status",
            status: "idle",
            parent_chat_id: null,
            agent_name: agentName,
          })
        }, 25)

        const html = widget ? widget.outerHTML : ""
        return Promise.resolve(new Response(html, { status: 200, headers: { "Content-Type": "text/html" } }))
      }

      window.__hitlOriginalFetch = originalFetch
    JS
  end

  def broadcast_status(status)
    page.execute_script(<<~JS, chat.id, agent.name, status)
      const panel = document.querySelector(".shared-chat--playground")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat-stream")
      controller.received({
        chat_id: arguments[0],
        type: "status",
        status: arguments[2],
        parent_chat_id: null,
        agent_name: arguments[1],
      })
    JS
  end

  def broadcast_chunk(content)
    page.execute_script(<<~JS, chat.id, agent.name, content)
      const panel = document.querySelector(".shared-chat--playground")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat-stream")
      controller.received({
        chat_id: arguments[0],
        type: "chunk",
        kind: "content",
        content: arguments[2],
        parent_chat_id: null,
        agent_name: arguments[1],
      })
    JS
  end

  def broadcast_tool_event(tool_call_id:, event:)
    page.execute_script(<<~JS, chat.id, agent.name, tool_call_id, event)
      const panel = document.querySelector(".shared-chat--playground")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat-stream")
      controller.received({
        chat_id: arguments[0],
        type: "tool_event",
        event: arguments[3],
        tool_call_id: arguments[2],
        tool_name: "ask_user_questions",
        display_name: "Ask User Questions",
        icon: "fa-solid fa-circle-question",
        widget_payload: {},
        parent_chat_id: null,
        agent_name: arguments[1],
      })
    JS
  end
end
