# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent Alpha streaming continuity", :js do
  let!(:tenant) do
    create(:tenant).tap(&:ensure_core_resources!)
  end
  let!(:user) { create(:user, :admin, tenant:) }

  before do
    create(:model, model_id: "gpt-4.1", provider: "openai")
    create(:system_preference, :configured)
  end

  it "keeps streamed assistant content across Turbo page navigation and finalizes in place" do
    open_admin_root
    chat_id = agent_alpha_chat_id
    Chat.find(chat_id).streaming!
    constrain_messages_height

    stream_thinking_across_navigation(chat_id)
    stream_content_with_persisted_thinking(chat_id)
    finalize_stream_with_persisted_thinking(chat_id)

    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__message--stable", visible: :all)
  end

  it "streams a second turn live after the first one completes" do
    open_admin_root
    chat_id = agent_alpha_chat_id
    Chat.find(chat_id).streaming!
    constrain_messages_height

    broadcast_status(chat_id, status: "streaming")
    broadcast_chunk(chat_id, "First reply")
    broadcast_status(chat_id, status: "idle")

    expect_streaming_message_promoted

    broadcast_status(chat_id, status: "streaming")
    broadcast_chunk(chat_id, "Second **live**")
    expect_streamed_markdown(text: "Second live", strong: "live")

    broadcast_chunk(chat_id, " reply")
    expect_streamed_markdown(text: "Second live reply", strong: "live")

    broadcast_status(chat_id, status: "idle")
    expect_streaming_message_promoted
    expect_messages_scrolled_to_bottom
  end

  it "renders live tools and subagents in the persisted shared style and stops shimmer on completion" do
    open_admin_root
    chat_id = agent_alpha_chat_id
    Chat.find(chat_id).streaming!

    broadcast_status(chat_id, status: "streaming")

    exercise_grouped_tool_stream(chat_id)
    exercise_subagent_branch_stream(chat_id)

    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__tool-call-name", text: "Mission Designer")
  end

  it "promotes a persisted generic subagent row when the child stream arrives" do
    open_admin_root
    chat = create_persisted_generic_subagent_row

    page.refresh

    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__composer", visible: :all)
    expect(agent_alpha_chat_id).to eq(chat.id.to_s)
    expect_generic_parent_subagent_tool_count(1)
    expect_subagent_branch_count(0)

    broadcast_child_subagent_output(chat)

    expect_subagent_transcript_markdown(text: "Live child output")
    expect_subagent_branch_count(1)
    expect_generic_parent_subagent_tool_count(0)
    expect_parent_tool_label_count("Mission Designer", 1)
  end

  it "resumes a child subagent stream after a full page refresh" do
    open_admin_root
    chat_id = agent_alpha_chat_id
    child_chat_id = chat_id.to_i + 20_000
    child_payload = subagent_child_payload(chat_id)
    Chat.find(chat_id).streaming!

    broadcast_status(chat_id, status: "streaming")
    broadcast_subagent_tool_event(chat_id, "start")
    expect_subagent_branch_running("Mission Designer")

    page.refresh

    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__composer", visible: :all)
    expect(agent_alpha_chat_id).to eq(chat_id.to_s)

    broadcast_status(child_chat_id, status: "streaming", phase: "thinking", **child_payload)
    broadcast_thinking(child_chat_id, "Recovering the child stream", **child_payload)
    expect_subagent_thinking("Recovering the child stream")

    broadcast_status(child_chat_id, status: "streaming", **child_payload)
    broadcast_chunk(child_chat_id, "Recovered **child** stream", **child_payload)
    expect_subagent_transcript_markdown(text: "Recovered child stream", strong: "child")

    broadcast_subagent_tool_event(chat_id, "complete")
    expect_subagent_branch_completed("Mission Designer")
    expect_subagent_branch_count(1)
  end

  it "reopens the latest selected chat after a full page refresh" do
    open_admin_root
    selected_chat = create_agent_alpha_chat(title: "Agent Alpha — Reopen Me")
    newest_chat = create_agent_alpha_chat(title: "Agent Alpha — Newest")

    click_link "Chats"
    expect_history_view_visible

    click_link "Reopen Me"
    expect_selected_chat_visible(selected_chat:, newest_chat:)

    page.refresh

    expect_selected_chat_visible(selected_chat:, newest_chat:)
  end

  it "refreshes the current agent page when a refresh payload targets the open record" do
    agent = create(:agent, operation: tenant.default_operation, name: "Refresh Me", model_id: "gpt-4.1")
    current_path = admin_agent_path(agent)

    open_admin_root
    page.execute_script("Turbo.visit(arguments[0])", current_path)

    expect(page).to have_current_path(current_path, ignore_query: true)
    expect(page).to have_css(".page-hero__record-title", text: "Refresh Me", visible: :all)
    expect(page).to have_css("turbo-frame#app-content-frame", visible: :all)
    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__composer", visible: :all)

    agent.update!(name: "Refreshed Agent")
    broadcast_agent_alpha_event(
      type: "refresh",
      chat_id: agent_alpha_chat_id,
      path: admin_agent_path(agent),
      current_path:,
    )

    expect_agent_show_refresh(name: "Refreshed Agent")
  end

  it "keeps the active stream mounted when a navigate payload moves the content frame" do
    open_admin_root
    chat_id = agent_alpha_chat_id
    Chat.find(chat_id).streaming!

    broadcast_status(chat_id, status: "streaming")
    broadcast_chunk(chat_id, "Still streaming")
    expect_streamed_markdown(text: "Still streaming")

    broadcast_agent_alpha_event(type: "navigate", chat_id:, path: admin_agents_path)

    expect(page).to have_current_path(admin_agents_path, ignore_query: true)
    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__message-content", text: "Still streaming")

    broadcast_chunk(chat_id, " after navigation")
    expect_streamed_markdown(text: "Still streaming after navigation")

    broadcast_status(chat_id, status: "idle")
    expect_streaming_message_promoted
  end

  it "updates the browser location when opening an agent from the index inside the content frame" do
    agent = create(:agent, operation: tenant.default_operation, name: "History Agent", model_id: "gpt-4.1")

    open_admin_root
    page.execute_script("Turbo.visit(arguments[0])", admin_agents_path)

    expect(page).to have_current_path(admin_agents_path, ignore_query: true)

    within(".page-content") do
      click_link "History Agent"
    end

    expect(page).to have_current_path(admin_agent_path(agent), ignore_query: true)
    expect_agent_show_refresh(name: "History Agent")
  end

  def expect_agent_show_refresh(name:)
    expect(page).to have_css(".page-hero__record-title", text: name, visible: :all)
    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__composer", visible: :all)
  end

  def open_admin_root
    visit tenant_login_path(tenant)
    fill_in "Email", with: user.email
    fill_in "Password", with: "Password123!"
    click_button "Sign In"

    expect(page).to have_current_path(admin_root_path, ignore_query: true)
    click_button nil, title: "Agent Alpha"
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__composer",
      visible: :all,
    )
  end

  def agent_alpha_chat_id
    find("#admin-agent-alpha-frame input[name='message[chat_id]']", visible: :all).value
  end

  def create_agent_alpha_chat(title:)
    create(
      :chat,
      :application_context,
      user:,
      agent: BuiltinAgents::Resolver.find!("agent_alpha", tenant:),
      model: Model.find_by!(model_id: "gpt-4.1"),
      title:,
    )
  end

  def expect_history_view_visible
    expect(page).to have_css("#admin-agent-alpha-frame .ms-chat-history-view", visible: :all)
  end

  def expect_selected_chat_visible(selected_chat:, newest_chat:)
    expect(page).to have_css("#admin-agent-alpha-frame .shared-chat__composer", visible: :all)
    expect(agent_alpha_chat_id).to eq(selected_chat.id.to_s)
    expect(agent_alpha_chat_id).not_to eq(newest_chat.id.to_s)
  end

  def broadcast_status(chat_id, status:, phase: nil, **payload)
    broadcast_agent_alpha_event(
      type: "status",
      chat_id:,
      status:,
      phase:,
      **payload,
    )
  end

  def broadcast_chunk(chat_id, text, **payload)
    broadcast_agent_alpha_event(type: "chunk", chat_id:, content: text, kind: "content", **payload)
  end

  def broadcast_thinking(chat_id, text, **payload)
    broadcast_agent_alpha_event(type: "chunk", chat_id:, content: text, kind: "thinking", **payload)
  end

  def broadcast_tool_event(chat_id, payload)
    broadcast_agent_alpha_event(
      type: "tool_event",
      chat_id:,
      icon: "fa-solid fa-wrench",
      **payload,
    )
  end

  def navigate_to_preferences
    page.execute_script("Turbo.visit(arguments[0])", admin_preferences_path)

    expect(page).to have_current_path(admin_preferences_path, ignore_query: true)
  end

  def constrain_messages_height
    page.execute_script(<<~JS)
      const messages = document.querySelector("#admin-agent-alpha-frame [data-chat-target='messages']")
      messages.style.maxHeight = "160px"
      messages.style.height = "160px"
      messages.style.overflowY = "auto"
    JS
  end

  def expect_agent_alpha_content(text)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__message-content",
      text:,
      visible: :all,
    )
  end

  def expect_streamed_markdown(text:, strong: nil, emphasis: nil)
    expect_agent_alpha_content(text)
    expect_strong_markdown(strong)
    expect_emphasis_markdown(emphasis)
  end

  def expect_agent_alpha_loader_markup_absent
    expect(page).to have_no_css("#admin-agent-alpha-frame .shared-chat__loading-shimmer", visible: :all)
  end

  def expect_agent_alpha_waiting_placeholder
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__bubble--placeholder",
      text: "Waiting for response",
      visible: :all,
    )
  end

  def expect_agent_alpha_waiting_placeholder_absent
    expect(page).to have_no_css(
      "#admin-agent-alpha-frame .shared-chat__bubble--placeholder",
      visible: :all,
    )
  end

  def expect_agent_alpha_thinking(text)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__thinking-body",
      text:,
      visible: :all,
    )
  end

  def expect_agent_alpha_thinking_collapsed
    expect(page).to have_css(
      "#admin-agent-alpha-frame details.shared-chat__thinking:not([open])",
      visible: :all,
    )
  end

  def expect_grouped_tool_running(label)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__tool-timeline-item.is-running .shared-chat__tool-call-name",
      text: label,
      visible: :all,
    )
  end

  def expect_grouped_tool_completed(label)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__tool-timeline-item.is-complete .shared-chat__tool-call-name",
      text: label,
      visible: :all,
    )
  end

  def expect_subagent_branch_running(label)
    branch_selector = "#admin-agent-alpha-frame .shared-chat__tool-timeline-item.is-running " \
                      "details.shared-chat__tool-timeline-branch[open] .shared-chat__tool-call-name"

    expect(page).to have_css(
      branch_selector,
      text: label,
      visible: :all,
    )
    expect(page).to have_css(
      "#admin-agent-alpha-frame details.shared-chat__tool-timeline-branch .shared-chat__subagent-empty",
      text: "No visible transcript yet.",
      visible: :all,
    )
  end

  def expect_subagent_branch_completed(label)
    branch_selector = "#admin-agent-alpha-frame .shared-chat__tool-timeline-item.is-complete " \
                      "details.shared-chat__tool-timeline-branch .shared-chat__tool-call-name"

    expect(page).to have_css(
      branch_selector,
      text: label,
      visible: :all,
    )

    branch_state = page.evaluate_script(<<~JS)
      (() => {
        const item = document.querySelector("#admin-agent-alpha-frame .shared-chat__tool-timeline-item--branch")
        const branch = item?.querySelector("details.shared-chat__tool-timeline-branch")
        return { open: branch?.open, complete: item?.classList.contains("is-complete") }
      })()
    JS

    expect(branch_state).to eq({ "open" => false, "complete" => true })
  end

  def expect_subagent_branch_count(count)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__tool-timeline-item--branch",
      count:,
      visible: :all,
    )
  end

  def create_persisted_generic_subagent_row
    Chat.find(agent_alpha_chat_id).tap do |chat|
      chat.streaming!
      message = create(:message, :assistant, chat:, content: "")
      create(
        :tool_call,
        message:,
        name: "ask_agent_mission_designer",
        tool_call_id: "call-persisted-subagent",
        display_name: "Mission Designer",
        icon: "fa-solid fa-robot",
        duration_ms: nil,
      )
    end
  end

  def broadcast_child_subagent_output(chat)
    child_chat_id = chat.id + 30_000
    child_payload = subagent_child_payload(chat.id)
    broadcast_status(child_chat_id, status: "streaming", **child_payload)
    broadcast_chunk(child_chat_id, "Live child output", **child_payload)
  end

  def expect_parent_tool_label_count(label, count)
    actual_count = page.evaluate_script(<<~JS)
      (() => Array.from(
        document.querySelectorAll(
          "#admin-agent-alpha-frame [data-chat-target='messages'] > .shared-chat__message--assistant > .shared-chat__assistant-panel .shared-chat__tool-call-name"
        )
      ).filter((element) => element.textContent.trim() === #{label.to_json}).length)()
    JS

    expect(actual_count).to eq(count)
  end

  def expect_generic_parent_subagent_tool_count(count)
    actual_count = page.evaluate_script(<<~JS)
      (() => document.querySelectorAll(
        "#admin-agent-alpha-frame [data-chat-target='messages'] > .shared-chat__message--assistant > .shared-chat__assistant-panel " +
        ".shared-chat__tool-timeline-item[data-tool-name='ask_agent_mission_designer']:not(.shared-chat__tool-timeline-item--branch)"
      ).length)()
    JS

    expect(actual_count).to eq(count)
  end

  def expect_subagent_transcript_markdown(text:, strong: nil)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__subagent-thread .shared-chat__message-content",
      text:,
      visible: :all,
    )

    return unless strong

    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__subagent-thread .shared-chat__message-content strong",
      text: strong,
      visible: :all,
    )
  end

  def expect_subagent_thinking(text)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__subagent-thread .shared-chat__thinking-body",
      text:,
      visible: :all,
    )
  end

  def expect_subagent_placeholder_absent
    expect(page).to have_no_css(
      "#admin-agent-alpha-frame .shared-chat__subagent-thread .shared-chat__subagent-empty",
      visible: :all,
    )
  end

  def expect_subagent_placeholder_not_shimmering
    expect(page).to have_no_css(
      "#admin-agent-alpha-frame .shared-chat__subagent-thread .shared-chat__subagent-empty.shared-chat__text-shimmer",
      visible: :all,
    )
  end

  def expect_subagent_child_tool_running(label)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__subagent-thread .shared-chat__tool-call-name",
      text: label,
      visible: :all,
    )
  end

  def expect_subagent_live_sequence
    sequence = page.evaluate_script(<<~JS)
      (() => Array.from(document.querySelectorAll("#admin-agent-alpha-frame .shared-chat__subagent-thread > .shared-chat__message")).map((message) => ({
        hasThinking: Boolean(message.querySelector(".shared-chat__thinking-body")?.textContent?.trim()),
        hasContent: Boolean(message.querySelector(".shared-chat__message-content")?.textContent?.trim()),
        toolCount: message.querySelectorAll(".shared-chat__tool-call, .shared-chat__tool-timeline-item").length,
      })))()
    JS

    expect(sequence).to eq(
      [
        { "hasThinking" => false, "hasContent" => false, "toolCount" => 1 },
        { "hasThinking" => true, "hasContent" => true, "toolCount" => 0 },
      ],
    )
  end

  def expect_parent_live_sequence_after_subagent
    sequence = page.evaluate_script(<<~JS)
      (() => Array.from(document.querySelectorAll("#admin-agent-alpha-frame [data-chat-target='messages'] > .shared-chat__message--assistant")).map((message) => ({
        hasThinking: Boolean(message.querySelector(":scope > .shared-chat__assistant-panel > .shared-chat__thinking .shared-chat__thinking-body")?.textContent?.trim()),
        hasContent: Boolean(message.querySelector(":scope > .shared-chat__assistant-panel > .shared-chat__assistant-content")?.textContent?.trim()),
        branchCount: message.querySelectorAll(":scope > .shared-chat__assistant-panel .shared-chat__tool-timeline-item--branch").length,
      })))()
    JS

    expect(sequence).to eq(
      [
        { "hasThinking" => false, "hasContent" => false, "branchCount" => 1 },
        { "hasThinking" => true, "hasContent" => true, "branchCount" => 0 },
      ],
    )
  end

  def expect_parent_live_sequence_after_subagent_content_only
    sequence = page.evaluate_script(<<~JS)
      (() => Array.from(document.querySelectorAll("#admin-agent-alpha-frame [data-chat-target='messages'] > .shared-chat__message--assistant")).map((message) => ({
        hasThinking: Boolean(message.querySelector(":scope > .shared-chat__assistant-panel > .shared-chat__thinking .shared-chat__thinking-body")?.textContent?.trim()),
        hasContent: Boolean(message.querySelector(":scope > .shared-chat__assistant-panel > .shared-chat__assistant-content")?.textContent?.trim()),
        branchCount: message.querySelectorAll(":scope > .shared-chat__assistant-panel .shared-chat__tool-timeline-item--branch").length,
      })))()
    JS

    expect(sequence).to include(hash_including("branchCount" => 1))
    expect(sequence).to include(hash_including("hasContent" => true))
    expect(sequence.any? { |message| message["hasContent"] && !message["hasThinking"] }).to be(true)
  end

  def subagent_child_payload(chat_id)
    {
      parent_chat_id: chat_id,
      agent_name: "Mission Designer",
    }
  end

  def child_tool_widget_payload
    {
      tool_widget_complete_messages_value: "[\"Mission read complete\"]",
      tool_widget_group_title_value: "",
      tool_widget_initial_phrase_value: "Reading the mission flow",
      tool_widget_running_interval_ms_value: "2200",
      tool_widget_running_messages_value: "[\"Reading the mission flow\"]",
      tool_widget_running_mode_value: "random",
    }
  end

  def broadcast_subagent_child_tool_event(child_chat_id, event, chat_id)
    broadcast_tool_event(child_chat_id,
                         {
                           event:,
                           tool_call_id: "child-call-1",
                           tool_name: "read_mission_flow",
                           display_name: "Read mission flow",
                           widget_payload: child_tool_widget_payload,
                           **subagent_child_payload(chat_id),
                         })
  end

  def stream_subagent_child_tool_activity(chat_id, child_chat_id, child_payload)
    broadcast_status(child_chat_id,
                     status: "streaming",
                     **child_payload,)
    broadcast_subagent_child_tool_event(child_chat_id, "start", chat_id)

    expect_subagent_child_tool_running("Read mission flow")
    expect_subagent_placeholder_absent

    broadcast_subagent_child_tool_event(child_chat_id, "complete", chat_id)
  end

  def stream_subagent_child_text(_chat_id, child_chat_id, child_payload)
    broadcast_status(child_chat_id,
                     status: "streaming",
                     phase: "thinking",
                     **child_payload,)
    broadcast_thinking(child_chat_id,
                       "Checking the **mission** flow",
                       **child_payload,)

    expect_subagent_thinking("Checking the **mission** flow")

    broadcast_status(child_chat_id,
                     status: "streaming",
                     **child_payload,)
    broadcast_chunk(child_chat_id,
                    "Mission **change** ready",
                    **child_payload,)

    expect_subagent_transcript_markdown(text: "Mission change ready", strong: "change")
    expect_subagent_placeholder_absent
  end

  def stream_subagent_child_transcript(chat_id, child_chat_id)
    child_payload = subagent_child_payload(chat_id)

    stream_subagent_child_tool_activity(chat_id, child_chat_id, child_payload)
    stream_subagent_child_text(chat_id, child_chat_id, child_payload)
    expect_subagent_live_sequence

    broadcast_status(child_chat_id,
                     status: "idle",
                     **child_payload,)
  end

  def broadcast_subagent_tool_event(chat_id, event)
    broadcast_tool_event(chat_id,
                         {
                           event:,
                           tool_call_id: "call-2",
                           tool_name: "ask_agent_mission_designer",
                           display_name: "Mission Designer",
                           widget_payload: ungrouped_tool_widget_payload,
                         })
  end

  def stream_thinking_across_navigation(chat_id)
    broadcast_status(chat_id, status: "streaming", phase: "thinking")
    broadcast_thinking(chat_id, "Working through the answer")

    expect_agent_alpha_thinking("Working through the answer")
    navigate_to_preferences
    expect_agent_alpha_thinking("Working through the answer")
  end

  def stream_content_with_persisted_thinking(chat_id)
    broadcast_status(chat_id, status: "streaming")
    expect_agent_alpha_thinking("Working through the answer")
    expect_agent_alpha_thinking_collapsed

    broadcast_chunk(chat_id, "Hello **world**")
    expect_streamed_markdown(text: "Hello world", strong: "world")
    expect_agent_alpha_thinking_collapsed

    broadcast_chunk(chat_id, " and _again_")
    expect_streamed_markdown(text: "Hello world and again", emphasis: "again")

    broadcast_chunk(chat_id, long_markdown_tail)
    expect_messages_scrolled_to_bottom
  end

  def exercise_grouped_tool_stream(chat_id)
    expect_agent_alpha_waiting_placeholder

    broadcast_grouped_tool_event(chat_id, "start")

    expect_grouped_tool_running("Lookup people")
    expect_agent_alpha_loader_markup_absent
    expect_agent_alpha_waiting_placeholder_absent

    broadcast_grouped_tool_event(chat_id, "complete")

    expect_grouped_tool_completed("Lookup people")
    expect_agent_alpha_waiting_placeholder_absent
  end

  def broadcast_grouped_tool_event(chat_id, event)
    broadcast_tool_event(chat_id,
                         {
                           event:,
                           tool_call_id: "call-1",
                           tool_name: "lookup_people",
                           display_name: "Lookup people",
                           widget_payload: grouped_tool_widget_payload,
                         })
  end

  def exercise_subagent_branch_stream(chat_id)
    child_chat_id = chat_id.to_i + 10_000
    broadcast_subagent_tool_event(chat_id, "start")

    expect_subagent_branch_running("Mission Designer")
    expect_parent_tool_label_count("Mission Designer", 1)
    expect_agent_alpha_loader_markup_absent
    expect_agent_alpha_waiting_placeholder_absent
    stream_subagent_child_transcript(chat_id, child_chat_id)

    broadcast_subagent_tool_event(chat_id, "complete")

    expect_subagent_branch_completed("Mission Designer")
    expect_parent_tool_label_count("Mission Designer", 1)
    expect_subagent_placeholder_not_shimmering
    expect_agent_alpha_waiting_placeholder_absent

    broadcast_status(chat_id, status: "streaming")
    broadcast_chunk(chat_id, "Parent **answer**")
    expect_streamed_markdown(text: "Parent answer", strong: "answer")

    broadcast_chunk(chat_id, " ready")
    expect_streamed_markdown(text: "Parent answer ready", strong: "answer")
    expect_parent_live_sequence_after_subagent_content_only
    expect_agent_alpha_waiting_placeholder_absent
  end

  def finalize_stream_with_persisted_thinking(chat_id)
    broadcast_status(chat_id, status: "idle")

    expect_streamed_markdown(text: "Hello world and again", emphasis: "again")
    expect_agent_alpha_thinking("Working through the answer")
    expect_agent_alpha_thinking_collapsed
    expect_agent_alpha_content("tail line")
    expect_streaming_message_promoted
    expect_messages_scrolled_to_bottom
    expect_agent_alpha_waiting_placeholder_absent
  end

  def expect_streaming_message_promoted
    expect(page).to have_no_css("#admin-agent-alpha-frame #streaming-message", visible: :all)
    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__message--stable",
      visible: :all,
    )
  end

  def expect_messages_scrolled_to_bottom
    scroll_metrics = page.evaluate_script(<<~JS)
      (() => {
        const messages = document.querySelector("#admin-agent-alpha-frame [data-chat-target='messages']")
        return {
          scrollTop: messages.scrollTop,
          scrollHeight: messages.scrollHeight,
          clientHeight: messages.clientHeight,
        }
      })()
    JS

    remaining = scroll_metrics["scrollHeight"] - scroll_metrics["scrollTop"] - scroll_metrics["clientHeight"]
    expect(remaining).to be <= 32
  end

  def long_markdown_tail
    "\n\n#{Array.new(48, "tail line").join("\n\n")}"
  end

  def grouped_tool_widget_payload
    {
      tool_widget_complete_messages_value: "[\"Lookup complete\"]",
      tool_widget_group_title_value: "Working on directory lookup",
      tool_widget_initial_phrase_value: "Looking up records",
      tool_widget_running_interval_ms_value: "2200",
      tool_widget_running_messages_value: "[\"Looking up records\"]",
      tool_widget_running_mode_value: "random",
    }
  end

  def ungrouped_tool_widget_payload
    {
      tool_widget_complete_messages_value: "[\"Mission Designer is ready\"]",
      tool_widget_group_title_value: "",
      tool_widget_initial_phrase_value: "Delegating the mission edit",
      tool_widget_running_interval_ms_value: "2200",
      tool_widget_running_messages_value: "[\"Delegating the mission edit\"]",
      tool_widget_running_mode_value: "random",
    }
  end

  def expect_strong_markdown(strong)
    return unless strong

    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__message-content strong",
      text: strong,
      visible: :all,
    )
  end

  def expect_emphasis_markdown(emphasis)
    return unless emphasis

    expect(page).to have_css(
      "#admin-agent-alpha-frame .shared-chat__message-content em",
      text: emphasis,
      visible: :all,
    )
  end

  def broadcast_agent_alpha_event(payload)
    page.execute_script(
      <<~JS,
        const element = document.getElementById("chat-stream-source")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "chat-stream")
        controller.received(JSON.parse(arguments[0]))
      JS
      payload.to_json,
    )
  end
end
