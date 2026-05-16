# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground chat input behavior", :js do
  let!(:tenant) do
    create(:tenant).tap(&:ensure_core_resources!)
  end
  let!(:operation) { tenant.default_operation }
  let!(:user) { create(:user, :admin, tenant:) }
  let!(:model) { create(:model, model_id: "gpt-4.1", provider: "openai") }
  let!(:connector) { create(:connector, :llm_provider, :enabled, tenant:) }
  let!(:agent) { create(:agent, operation:, llm_connector: connector, model_id: "gpt-4.1") }
  let!(:chat) { create(:chat, agent:, user:, model:) }

  before do
    create(
      :system_preference,
      :configured,
      tenant:,
      llm_connector: connector,
      model_id: "gpt-4.1",
    )
    create(:message, chat:, role: :user, content: "first question")
    create(:message, chat:, role: :assistant, content: "first answer")
    create(:message, chat:, role: :user, content: "second question")
  end

  it "recalls recent user messages with arrow keys and restores the draft" do
    open_playground_chat
    input = composer_input

    input.click
    input.send_keys("draft message")
    input.send_keys(:arrow_up)
    expect(composer_input.value).to eq("second question")

    composer_input.send_keys(:arrow_up)
    expect(composer_input.value).to eq("first question")

    composer_input.send_keys(:arrow_down)
    expect(composer_input.value).to eq("second question")

    composer_input.send_keys(:arrow_down)
    expect(composer_input.value).to eq("draft message")
  end

  it "submits with Enter and adds the new message to local history" do
    open_playground_chat
    submitted_text = "browser history message"
    input = composer_input

    input.click
    input.send_keys(submitted_text)
    input.send_keys(:enter)

    expect(page).to have_css(".shared-chat__message--user .shared-chat__message-content", text: submitted_text)
    expect(composer_input.value).to eq("")

    composer_input.click
    composer_input.send_keys(:arrow_up)
    expect(composer_input.value).to eq(submitted_text)
  end

  it "renders top-level live streams as the main assistant response" do
    open_playground_chat

    broadcast_top_level_stream("Main agent reply")

    expect(page).to have_css(
      ".shared-chat--playground #streaming-message .shared-chat__message-content",
      text: "Main agent reply",
    )
    expect(page).to have_no_css(".shared-chat--playground .shared-chat__tool-timeline-branch", visible: :all)
    expect(page).to have_no_css(".shared-chat--playground .shared-chat__subagent-thread", visible: :all)
  end

  it "switches agents inside the content frame and keeps live streaming working" do
    second_agent = create(:agent, operation:, llm_connector: connector, model_id: "gpt-4.1", name: "Switch Target")
    second_chat = create(:chat, agent: second_agent, user:, model:)

    open_playground_chat
    page.execute_script("document.body.dataset.playgroundProbe = 'alive'")

    switch_playground_agent(second_agent.id)

    expect(page).to have_current_path(admin_playground_chat_path(second_chat), ignore_query: true)
    expect(page).to have_css(".page-hero__record-title", text: "Switch Target", visible: :all)
    expect(page.evaluate_script("document.body.dataset.playgroundProbe")).to eq("alive")

    broadcast_top_level_stream("Switched agent reply", chat_id: second_chat.id, agent_name: second_agent.name)

    expect(page).to have_css(
      ".shared-chat--playground #streaming-message .shared-chat__message-content",
      text: "Switched agent reply",
    )
  end

  it "keeps multiline drafts intact when ArrowUp is pressed below the first line" do
    open_playground_chat
    multiline_draft = "first line\nsecond line"

    composer_input.click
    set_composer_value(multiline_draft, cursor_position: multiline_draft.length)
    dispatch_composer_keydown("ArrowUp")

    expect(composer_input.value).to eq(multiline_draft)
  end

  it "keeps multiline drafts intact when ArrowUp is pressed mid-way through the first line" do
    open_playground_chat
    multiline_draft = "first line\nsecond line"

    composer_input.click
    set_composer_value(multiline_draft, cursor_position: 3)
    dispatch_composer_keydown("ArrowUp")

    expect(composer_input.value).to eq(multiline_draft)
  end

  it "keeps recalled multiline history intact when ArrowDown is pressed before the end of the last line" do
    multiline_history = "multi line one\nmulti line two"
    create(:message, chat:, role: :user, content: multiline_history)

    open_playground_chat

    composer_input.click
    composer_input.send_keys(:arrow_up)
    expect(composer_input.value).to eq(multiline_history)

    position_composer_selection(multiline_history.index("two"))
    dispatch_composer_keydown("ArrowDown")

    expect(composer_input.value).to eq(multiline_history)
  end

  def open_playground_chat
    visit tenant_login_path(tenant)
    fill_in "Email", with: user.email
    fill_in "Password", with: "Password123!"
    click_button "Sign In"
    expect(page).to have_current_path(admin_root_path, ignore_query: true)

    visit admin_playground_chat_path(chat)
  end

  def composer_input
    first(".shared-chat--playground .shared-chat__input", minimum: 1)
  end

  def set_composer_value(value, cursor_position: value.length)
    page.execute_script(<<~JS, composer_input.native, value, cursor_position)
      arguments[0].value = arguments[1]
      arguments[0].dispatchEvent(new Event("input", { bubbles: true }))
      arguments[0].selectionStart = arguments[2]
      arguments[0].selectionEnd = arguments[2]
    JS
  end

  def position_composer_selection(cursor_position)
    page.execute_script(<<~JS, composer_input.native, cursor_position)
      arguments[0].selectionStart = arguments[1]
      arguments[0].selectionEnd = arguments[1]
    JS
  end

  def dispatch_composer_keydown(key)
    page.execute_script(<<~JS, composer_input.native, key)
      arguments[0].dispatchEvent(new KeyboardEvent("keydown", { key: arguments[1], bubbles: true }))
    JS
  end

  def switch_playground_agent(agent_id)
    page.execute_script(<<~JS, agent_id)
      const select = document.querySelector('.playground-header-agent-form select[name="agent_id"]')
      select.value = String(arguments[0])
      select.dispatchEvent(new Event("change", { bubbles: true }))
    JS
  end

  def broadcast_top_level_stream(content, chat_id: chat.id, agent_name: agent.name)
    page.execute_script(<<~JS, chat_id, agent_name, content)
      const panel = document.querySelector(".shared-chat--playground")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(panel, "chat-stream")
      controller.received({
        type: "status",
        chat_id: arguments[0],
        status: "streaming",
        parent_chat_id: null,
        agent_name: arguments[1],
      })
      controller.received({
        type: "chunk",
        chat_id: arguments[0],
        content: arguments[2],
        kind: "content",
        parent_chat_id: null,
        agent_name: arguments[1],
      })
    JS
  end

  def open_agent_alpha_panel
    find('.ms-sidebar-tab-btn[data-sidebar-tab="assistant"]', visible: :all).click
    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__input", visible: :all)
  end
end
