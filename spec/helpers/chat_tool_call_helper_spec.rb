# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatToolCallHelper do
  describe "tool call metadata helpers" do
    def build_human_in_the_loop_arguments(prompt_text: nil)
      Capabilities::HumanInTheLoop::ToolCallState.build(
        prompt_text:,
        raw_questions: [{ prompt: "Which color should I use?", options: ["Red", "Blue"], label: "Color" }],
        capability: build(:capabilities_human_in_the_loop_standalone),
      ).to_h
    end

    def build_answered_human_in_the_loop_arguments(prompt_text: nil)
      Capabilities::HumanInTheLoop::ToolCallState
        .from_arguments(build_human_in_the_loop_arguments(prompt_text:))
        .answered_with(
          "question_1" => {
            "selected_option" => "Blue",
            "answer" => "Blue",
          },
        ).to_h
    end

    def build_subagent_fixture_agents(include_plain_tool:)
      operation = OperationFactoryHelper.default_operation
      parent_agent = create(:agent, operation:)
      mission_designer = create(:agent, operation:, name: "Mission Designer")
      analyst = create(:agent, operation:, name: "Research Analyst") if include_plain_tool
      parent_agent.update!(subagent_ids: [mission_designer.id, analyst&.id].compact)

      { parent_agent:, mission_designer: }
    end

    def create_message_at(chat:, role:, content:, at:)
      create(:message, role.to_sym, chat:, content:, created_at: at)
    end

    def create_tool_call_at(message:, name:, at:)
      create(:tool_call, message:, name:, created_at: at)
    end

    def build_parent_tool_message(chat:, start_at:, include_plain_tool:)
      message = create_message_at(chat:, role: :assistant, content: nil, at: start_at)
      subagent_call = create_tool_call_at(
        message:,
        name: "ask_agent_mission_designer",
        at: start_at + 1.second,
      )
      plain_call = create_tool_call_at(message:, name: "plain_tool", at: start_at + 2.seconds) if include_plain_tool

      { message:, subagent_call:, plain_call: }
    end

    def build_subagent_child_chat(chat:, mission_designer:, start_at:)
      child_chat = create(
        :chat,
        parent_chat: chat,
        agent: mission_designer,
        title: "Subagent: Mission Designer",
        created_at: start_at + 5.seconds,
      )
      create_message_at(chat: child_chat, role: :user, content: "Design this workflow", at: start_at + 6.seconds)
      create_message_at(chat: child_chat, role: :assistant, content: "Here is the plan", at: start_at + 7.seconds)

      child_chat
    end

    def build_parent_follow_up_message(chat:, start_at:, include_plain_tool:)
      create(
        :message,
        :user,
        chat:,
        content: include_plain_tool ? "Thanks" : "Continue",
        created_at: start_at + 20.seconds,
      )
    end

    def build_subagent_transcript_fixture(start_at:, include_plain_tool: false)
      agents = build_subagent_fixture_agents(include_plain_tool:)
      chat = create(:chat, :user_context, user: create(:user), agent: agents[:parent_agent])
      tool_message = build_parent_tool_message(
        chat:,
        start_at:,
        include_plain_tool:,
      )
      child_chat = build_subagent_child_chat(
        chat:,
        mission_designer: agents[:mission_designer],
        start_at:,
      )
      build_parent_follow_up_message(chat:, start_at:, include_plain_tool:)

      {
        chat:,
        tool_message: tool_message[:message],
        subagent_call: tool_message[:subagent_call],
        plain_call: tool_message[:plain_call],
        child_chat:,
      }
    end

    def build_repeated_subagent_tool_only_fixture(count:, start_at:)
      agents = build_subagent_fixture_agents(include_plain_tool: false)
      chat = create(:chat, :user_context, user: create(:user), agent: agents[:parent_agent])

      child_chats = Array.new(count) do |index|
        create_repeated_subagent_child_chat(
          chat:,
          mission_designer: agents[:mission_designer],
          index:,
          start_at:,
        )
      end

      create_message_at(chat:, role: :user, content: "Done", at: start_at + (count * 10).seconds)

      { chat:, child_chats: }
    end

    def create_repeated_subagent_child_chat(chat:, mission_designer:, index:, start_at:)
      message_at = start_at + (index * 10).seconds
      message = create_message_at(chat:, role: :assistant, content: nil, at: message_at)
      create_tool_call_at(message:, name: "ask_agent_mission_designer", at: message_at + 1.second)
      child_chat = create(
        :chat,
        parent_chat: chat,
        agent: mission_designer,
        title: "Subagent: Mission Designer #{index + 1}",
        created_at: message_at + 2.seconds,
      )
      create_message_at(
        chat: child_chat,
        role: :assistant,
        content: "Subagent answer #{index + 1}",
        at: message_at + 3.seconds,
      )
      child_chat
    end

    it "prefers persisted tool call metadata when available" do
      tool_call = build_stubbed(
        :tool_call,
        name: "read_mission_flow",
        display_name: "Custom Flow Label",
        icon: "fa-solid fa-star",
      )

      expect(helper.chat_tool_call_display_name(tool_call)).to eq("Custom Flow Label")
      expect(helper.chat_tool_call_icon(tool_call)).to eq("fa-solid fa-star")
    end

    it "falls back to resolver metadata when persisted values are missing" do
      tool_call = build_stubbed(:tool_call, name: "read_mission_flow", display_name: nil, icon: nil)

      expect(helper.chat_tool_call_display_name(tool_call)).to eq("Read Mission Flow")
      expect(helper.chat_tool_call_icon(tool_call)).to eq("fa-solid fa-diagram-project")
    end

    it "merges persisted and resolved metadata when only one persisted field is present" do
      tool_call = build_stubbed(:tool_call, name: "read_mission_flow", display_name: "Stored Label", icon: nil)

      expect(helper.chat_tool_call_display_name(tool_call)).to eq("Stored Label")
      expect(helper.chat_tool_call_icon(tool_call)).to eq("fa-solid fa-diagram-project")
    end

    it "returns generic metadata for blank tool calls" do
      expect(helper.chat_tool_call_display_name(nil)).to eq("Tool Call")
      expect(helper.chat_tool_call_icon(nil)).to eq("fa-solid fa-wrench")
    end

    it "returns no visible messages for a blank chat" do
      expect(helper.chat_visible_messages(nil)).to eq([])
    end

    it "returns widget controller data for the shared chat badge" do
      tool_call = build_stubbed(:tool_call, name: "read_mission_flow", display_name: nil, icon: nil)

      data = helper.chat_tool_call_widget_data(tool_call, status: :complete)

      expect(data[:controller]).to eq("tool-widget")
      expect(data[:tool_widget_status_value]).to eq(:complete)
      expect(data[:tool_widget_group_title_value]).to eq("Working on the mission flow")
      expect(JSON.parse(data[:tool_widget_complete_messages_value])).to include("Mission flow snapshot loaded.")
      expect(data[:tool_widget_initial_phrase_value]).to be_present
    end

    it "groups consecutive tool calls that share a group title" do
      grouped_tool_call = build_stubbed(:tool_call, name: "read_mission_flow", display_name: nil, icon: nil)
      grouped_tool_call_two = build_stubbed(:tool_call, name: "validate_flow", display_name: nil, icon: nil)
      plain_tool_call = build_stubbed(:tool_call, name: "plain_tool", display_name: nil, icon: nil)

      entries = helper.chat_tool_call_render_entries([grouped_tool_call, grouped_tool_call_two, plain_tool_call])
      expected_entries = [
        [:group, "Working on the mission flow", 2],
        [:group, "", 1],
      ]

      expect(entries.map { |entry| [entry[:kind], entry[:group_title], entry[:items].size] }).to eq(expected_entries)
    end

    it "marks unfinished persisted tool calls as running while the chat is streaming" do
      tool_call = create(
        :tool_call,
        message: create(
          :message,
          :assistant,
          chat: create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "streaming"),
          content: nil,
        ),
        name: "manage_edges",
        duration_ms: nil,
      )

      expect(helper.chat_tool_call_status(tool_call)).to eq(:running)
    end

    it "collapses consecutive grouped tool-only assistant messages into one render entry" do
      chat = create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "streaming")
      first_message = create(:message, :assistant, chat:, content: nil)
      second_message = create(:message, :assistant, chat:, content: nil)
      create(:tool_call, message: first_message, name: "read_mission_flow", duration_ms: 220)
      create(:tool_call, message: second_message, name: "manage_edges", duration_ms: nil)

      entries = helper.chat_message_render_entries(chat.messages.visible.order(:created_at).to_a)

      expect(entries.size).to eq(1)
      expect(entries.first[:kind]).to eq(:tool_group_message)
      expect(entries.first[:group_title]).to eq("Working on the mission flow")
      expect(entries.first[:status]).to eq(:running)
      expect(entries.first[:items].pluck(:status)).to eq([:complete, :running])
    end

    it "keeps the trailing grouped block running while the chat is still streaming" do
      chat = create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "streaming")
      first_message = create(:message, :assistant, chat:, content: nil)
      second_message = create(:message, :assistant, chat:, content: nil)
      create(:tool_call, message: first_message, name: "read_mission_flow", duration_ms: 180)
      create(:tool_call, message: second_message, name: "manage_edges", duration_ms: 210)

      entries = helper.chat_message_render_entries(chat.messages.visible.order(:created_at).to_a)

      expect(entries.first[:status]).to eq(:running)
      expect(entries.first[:items].pluck(:status)).to eq([:complete, :complete])
    end

    it "leaves non-group trailing entries unchanged" do
      chat = create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "streaming")
      create(:message, :assistant, chat:, content: "Working on it")

      entries = helper.chat_message_render_entries(chat.messages.visible.order(:created_at).to_a)

      expect(entries).to contain_exactly(include(kind: :message))
    end

    it "returns no render entries for an empty transcript" do
      expect(helper.chat_message_render_entries([])).to eq([])
    end

    it "marks only the last assistant entry in a turn as actionable", :aggregate_failures do
      chat = create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "idle")
      create(:message, :user, chat:, content: "Summarize this")
      create(:message, :assistant, chat:, content: "First pass")
      tool_message = create(:message, :assistant, chat:, content: nil)
      create(:tool_call, message: tool_message, name: "read_mission_flow", duration_ms: 180)
      final_message = create(:message, :assistant, chat:, content: "Final answer")

      entries = helper.chat_message_render_entries(chat.messages.visible.order(:created_at).to_a)

      expect(entries.pluck(:kind)).to eq([:message, :message, :tool_group_message, :message])
      expect(entries[1][:action_message]).to be_nil
      expect(entries[2][:action_message]).to be_nil
      expect(entries[3][:action_message]).to eq(final_message)
      expect(entries[3][:action_copy_text]).to include("First pass")
      expect(entries[3][:action_copy_text]).to include("Read Mission Flow")
      expect(entries[3][:action_copy_text]).to include("Final answer")
      expect(entries[3][:action_copy_text]).not_to include("Summarize this")
    end

    it "attaches turn actions to the last grouped tool entry when a turn ends on tools", :aggregate_failures do
      chat = create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "idle")
      create(:message, :user, chat:, content: "Continue")
      create(:message, :assistant, chat:, content: "Working on it")
      final_tool_message = create(:message, :assistant, chat:, content: nil)
      create(:tool_call, message: final_tool_message, name: "manage_edges", duration_ms: 210)

      entries = helper.chat_message_render_entries(chat.messages.visible.order(:created_at).to_a)
      tool_entry = entries.last

      expect(tool_entry[:kind]).to eq(:tool_group_message)
      expect(tool_entry[:action_message]).to eq(final_tool_message)
      expect(tool_entry[:action_copy_text]).to include("Working on it")
      expect(tool_entry[:action_copy_text]).to include("Manage Edges")
      expect(tool_entry[:action_copy_text]).not_to include("Continue")
    end

    it "returns nil grouped entries for non-tool-only messages", :aggregate_failures do
      user_message = build_stubbed(:message, :user, content: "Hello")
      assistant_message = build_stubbed(:message, :assistant, content: "Visible reply")

      expect(helper.send(:grouped_render_entry_for_message, user_message)).to be_nil
      expect(helper.send(:grouped_render_entry_for_message, assistant_message)).to be_nil
    end

    it "returns the expected tool call state labels" do
      expect(helper.chat_tool_call_state_label(:running)).to eq("In progress")
      expect(helper.chat_tool_call_state_label(:complete)).to eq("Completed")
    end

    it "classifies assistant and user render entries", :aggregate_failures do
      assistant_entry = { kind: :message, message: build_stubbed(:message, :assistant, content: "Hi") }
      user_entry = { kind: :message, message: build_stubbed(:message, :user, content: "Hello") }
      message_less_entry = { kind: :message, message: nil }
      tool_group_entry = { kind: :tool_group_message, items: [] }

      expect(helper.send(:assistant_render_entry?, assistant_entry)).to be(true)
      expect(helper.send(:assistant_render_entry?, tool_group_entry)).to be(true)
      expect(helper.send(:assistant_render_entry?, user_entry)).to be(false)
      expect(helper.send(:assistant_render_entry?, message_less_entry)).to be_nil
      expect(helper.send(:assistant_render_entry?, nil)).to be(false)
      expect(helper.send(:user_render_entry?, user_entry)).to be(true)
      expect(helper.send(:user_render_entry?, assistant_entry)).to be(false)
      expect(helper.send(:user_render_entry?, message_less_entry)).to be_nil
      expect(helper.send(:user_render_entry?, nil)).to be(false)
    end

    it "resolves assistant action messages only for assistant entries", :aggregate_failures do
      assistant_message = build_stubbed(:message, :assistant, content: "Reply")
      user_message = build_stubbed(:message, :user, content: "Prompt")
      tool_group_entry = { kind: :tool_group_message, source_message: assistant_message, items: [] }

      expect(helper.send(:assistant_action_message, tool_group_entry)).to eq(assistant_message)
      expect(
        helper.send(:assistant_action_message, { kind: :message, message: assistant_message }),
      ).to eq(assistant_message)
      expect(helper.send(:assistant_action_message, { kind: :message, message: user_message })).to be_nil
      expect(helper.send(:assistant_action_message, { kind: :message, message: nil })).to be_nil
      expect(helper.send(:assistant_action_message, nil)).to be_nil
    end

    it "ignores entries without assistant action targets when annotating turns", :aggregate_failures do
      assistant_message = build_stubbed(:message, :assistant, content: "Reply")
      entries = [
        { kind: :message, message: nil },
        { kind: :system },
        { kind: :message, message: assistant_message },
      ]

      helper.send(:annotate_assistant_turn_actions!, entries)

      expect(entries[0][:action_message]).to be_nil
      expect(entries[1][:action_message]).to be_nil
      expect(entries[2][:action_message]).to eq(assistant_message)
    end

    it "leaves turn actions blank when the last entry has no assistant action message" do
      entries = [{ kind: :message, message: nil }]

      helper.send(:assign_assistant_turn_actions!, entries)

      expect(entries.first[:action_message]).to be_nil
      expect(entries.first[:action_copy_text]).to be_nil
    end

    it "returns empty assistant turn copy text when nothing is copyable" do
      entry = { kind: :message, message: build_stubbed(:message, :user, content: "Prompt") }

      expect(helper.send(:assistant_turn_copy_text, [entry])).to eq("")
    end

    it "returns no copy text for nil and unknown assistant entries", :aggregate_failures do
      expect(helper.send(:assistant_entry_copy_text, nil)).to be_nil
      expect(helper.send(:assistant_entry_copy_text, { kind: :system })).to be_nil
      expect(helper.send(:assistant_message_copy_text, nil)).to be_nil
      expect(helper.send(:assistant_message_copy_text, build_stubbed(:message, :user, content: "Prompt"))).to be_nil
    end

    it "serializes tool group items with label-only and phrase-only rows", :aggregate_failures do
      expect(
        helper.send(:tool_group_item_copy_text, { label: "Read Mission Flow", phrase: "" }),
      ).to eq("- Read Mission Flow")
      expect(helper.send(:tool_group_item_copy_text, { label: "", phrase: "Working" })).to eq("- Working")
      expect(helper.send(:tool_group_item_copy_text, { label: "", phrase: "" })).to be_nil
    end

    it "skips blank tool group item lines when building copy text" do
      entry = {
        group_title: "Working on the mission flow",
        items: [
          { label: "", phrase: "" },
          { label: "Read Mission Flow", phrase: "" },
        ],
      }

      expect(helper.send(:tool_group_entry_copy_text, entry)).to eq(
        "Working on the mission flow\n- Read Mission Flow",
      )
    end

    it "does not replace an existing grouped source message with a blank source message" do
      first_source = build_stubbed(:message, :assistant, content: nil)
      entries = [
        {
          kind: :tool_group_message,
          group_title: "",
          items: [{ label: "Read Mission Flow" }],
          status: :complete,
          source_message: first_source,
        },
      ]

      helper.send(
        :append_grouped_chat_message_render_entry,
        entries,
        {
          kind: :tool_group_message,
          group_title: "",
          items: [{ label: "Manage Edges" }],
          status: :complete,
          source_message: nil,
        },
      )

      expect(entries.first[:items].size).to eq(2)
      expect(entries.first[:source_message]).to eq(first_source)
    end

    it "does not keep grouped entries running once the chat stops streaming" do
      chat = create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "idle")
      first_message = create(:message, :assistant, chat:, content: nil)
      second_message = create(:message, :assistant, chat:, content: nil)
      create(:tool_call, message: first_message, name: "read_mission_flow", duration_ms: 180)
      create(:tool_call, message: second_message, name: "manage_edges", duration_ms: 210)

      entries = helper.chat_message_render_entries(chat.messages.visible.order(:created_at).to_a)

      expect(entries.first[:status]).to eq(:complete)
      expect(entries.first[:items].pluck(:status)).to eq([:complete, :complete])
    end

    it "leaves grouped entries unchanged when no trailing message is available" do
      entries = [{ kind: :tool_group_message, status: :complete, items: [] }]

      helper.send(:keep_trailing_tool_group_running!, entries, [])

      expect(entries.first[:status]).to eq(:complete)
    end

    it "leaves empty entries unchanged" do
      entries = []

      helper.send(:keep_trailing_tool_group_running!, entries, [])

      expect(entries).to be_empty
    end

    it "leaves grouped entries unchanged when the trailing message has no chat" do
      entries = [{ kind: :tool_group_message, status: :complete, items: [] }]
      messages = [Struct.new(:chat).new(nil)]

      helper.send(:keep_trailing_tool_group_running!, entries, messages)

      expect(entries.first[:status]).to eq(:complete)
    end

    it "returns nil for grouped message entries when the message is blank" do
      expect(helper.send(:grouped_chat_message_render_entry, nil)).to be_nil
    end

    it "does not collapse tool-only messages that render custom widgets" do
      tool_message = create(
        :message,
        :assistant,
        chat: create(:chat, :user_context, user: create(:user), agent: create(:agent)),
        content: nil,
      )
      create(
        :tool_call,
        message: tool_message,
        name: "ask_user_questions",
        display_name: nil,
        icon: nil,
        arguments: build_human_in_the_loop_arguments,
      )

      entries = helper.chat_message_render_entries([tool_message])

      expect(entries.first[:kind]).to eq(:message)
    end

    it "skips grouped timeline collapsing when a visible tool call owns a custom widget" do
      tool_call = Object.new
      tool_call.define_singleton_method(:tool_call_widget_render_config) do
        { partial: "widgets/demo", locals: {}, view_path: nil }
      end

      message = Struct.new(:tool_calls, :content) do
        def assistant? = true
      end.new([tool_call], nil)

      expect(helper.send(:visible_groupable_tool_calls, message)).to eq([])
    end

    it "returns no groupable tool calls when shared rendering cannot form a tool chain" do
      tool_call = Object.new
      message = Struct.new(:tool_calls, :content) do
        def assistant? = true
      end.new([tool_call], nil)

      allow(helper).to receive(:chat_tool_call_badge_visible?).with(tool_call).and_return(true)
      allow(helper).to receive(:grouped_render_entry_for_tool_calls).with([tool_call], message:).and_return(nil)

      expect(helper.send(:visible_groupable_tool_calls, message)).to eq([])
    end

    it "returns nil when tool calls do not reduce to one shared group entry" do
      tool_call = build_stubbed(:tool_call)
      render_entries = [
        { kind: :group, group_title: "", items: [{}] },
        { kind: :group, group_title: "", items: [{}] },
      ]

      allow(helper).to receive(:chat_tool_call_render_entries)
        .with([tool_call], message: nil)
        .and_return(render_entries)

      expect(helper.send(:grouped_render_entry_for_tool_calls, [tool_call])).to be_nil
    end

    it "collapses tool-only messages without a shared grouped title into the shared tool chain" do
      tool_message = create(
        :message,
        :assistant,
        chat: create(:chat, :user_context, user: create(:user), agent: create(:agent), status: "streaming"),
        content: nil,
      )
      create(:tool_call, message: tool_message, name: "plain_tool", display_name: nil, icon: nil, duration_ms: nil)

      entries = helper.chat_message_render_entries([tool_message])

      expect(entries.first[:kind]).to eq(:tool_group_message)
      expect(entries.first[:group_title]).to eq("")
      expect(entries.first[:status]).to eq(:running)
    end

    it "treats tool calls without an attached message or chat as complete" do
      detached_tool_call = build_stubbed(:tool_call, message: nil, duration_ms: nil)
      chatless_message_tool_call = build_stubbed(
        :tool_call,
        message: build_stubbed(:message, chat: nil, content: nil),
        duration_ms: nil,
      )

      expect(helper.chat_tool_call_status(detached_tool_call)).to eq(:complete)
      expect(helper.chat_tool_call_status(chatless_message_tool_call)).to eq(:complete)
    end

    it "treats non-trackable tool call objects as complete" do
      expect(helper.chat_tool_call_status(Object.new)).to eq(:complete)
    end

    it "returns false when custom widget detection raises" do
      broken_tool_call = Object.new
      broken_tool_call.define_singleton_method(:tool_call_widget_render_config) { raise StandardError, "boom" }

      expect(helper.send(:tool_call_has_custom_widget?, broken_tool_call)).to be(false)
    end

    it "appends consecutive plain tool calls into one tool-chain entry" do
      first_tool_call = Struct.new(:duration_ms).new(nil)
      second_tool_call = Struct.new(:duration_ms).new(nil)
      first_presentation = ToolCalls::Presentation.new(display_name: "Lookup A", icon: "fa-solid fa-wrench")
      second_presentation = ToolCalls::Presentation.new(display_name: "Lookup B", icon: "fa-solid fa-wrench")

      allow(helper).to receive(:chat_tool_call_presentation).with(first_tool_call).and_return(first_presentation)
      allow(helper).to receive(:chat_tool_call_presentation).with(second_tool_call).and_return(second_presentation)
      allow(helper).to receive(:chat_tool_call_widget_data).and_return({})

      entries = helper.chat_tool_call_render_entries([first_tool_call, second_tool_call])

      expect(entries.size).to eq(1)
      expect(entries.first[:kind]).to eq(:group)
      expect(entries.first[:group_title]).to eq("")
      expect(entries.first[:items].size).to eq(2)
    end

    it "starts a new group entry when consecutive group titles differ" do
      first_tool_call = Struct.new(:duration_ms).new(nil)
      second_tool_call = Struct.new(:duration_ms).new(nil)
      first_presentation = ToolCalls::Presentation.new(
        display_name: "Read Flow",
        icon: "fa-solid fa-diagram-project",
        group_title: "Working on the mission flow",
      )
      second_presentation = ToolCalls::Presentation.new(
        display_name: "Warehouse Lookup",
        icon: "fa-solid fa-database",
        group_title: "Running the warehouse tool",
      )

      allow(helper).to receive(:chat_tool_call_presentation).with(first_tool_call).and_return(first_presentation)
      allow(helper).to receive(:chat_tool_call_presentation).with(second_tool_call).and_return(second_presentation)
      allow(helper).to receive(:chat_tool_call_widget_data).and_return({})

      entries = helper.chat_tool_call_render_entries([first_tool_call, second_tool_call])

      expect(entries.pluck(:group_title)).to eq(
        ["Working on the mission flow", "Running the warehouse tool"],
      )
    end

    it "attaches matching subagent child chats to tool call render items" do
      fixture = build_subagent_transcript_fixture(
        start_at: Time.zone.parse("2026-04-24 10:00:00"),
        include_plain_tool: true,
      )

      entries = helper.chat_tool_call_render_entries(
        fixture[:tool_message].tool_calls.order(:created_at).to_a,
        message: fixture[:tool_message],
      )
      items = entries.flat_map { |entry| entry[:items] }

      expect(items.find { |item| item[:tool_call] == fixture[:subagent_call] }[:child_chat]).to eq(fixture[:child_chat])
      expect(items.find { |item| item[:tool_call] == fixture[:plain_call] }[:child_chat]).to be_nil
    end

    it "renders a nested transcript for subagent tool rows", :aggregate_failures do
      fixture = build_subagent_transcript_fixture(start_at: Time.zone.parse("2026-04-24 11:00:00"))

      item = helper.chat_tool_call_render_entries(
        [fixture[:subagent_call]],
        message: fixture[:tool_message],
      ).first[:items].first
      html = helper.render(
        partial: "shared/chat/tool_call_group",
        locals: { group_title: "", items: [item], status: item[:status] },
      )

      expect(html).to include("Mission Designer")
      expect(html).to include("Here is the plan")
      expect(html).to include("shared-chat__tree-children")
      expect(html).to include("fa-user-secret")
      expect(html).to include("shared-chat__section-label")
      expect(html).not_to include("Design this workflow")
      expect(html).not_to include("deepseek-v4-flash")
      expect(html).not_to include("shared-chat__tool-call-state")
    end

    it "preserves every subagent branch when tool-only messages collapse", :aggregate_failures do
      fixture = build_repeated_subagent_tool_only_fixture(
        count: 5,
        start_at: Time.zone.parse("2026-04-24 12:00:00"),
      )

      entries = helper.chat_message_render_entries(fixture[:chat].messages.visible.order(:created_at, :id).to_a)
      group_entry = entries.find { |entry| entry[:kind] == :tool_group_message }
      child_chats = group_entry[:items].pluck(:child_chat)
      html = helper.render(
        partial: "shared/chat/tool_group_message",
        locals: { group_title: group_entry[:group_title], items: group_entry[:items], status: group_entry[:status] },
      )

      expect(child_chats).to eq(fixture[:child_chats])
      expect(html.scan("shared-chat__tool-timeline-branch").size).to eq(5)
      expect(html).to include("Subagent answer 1")
      expect(html).to include("Subagent answer 5")
    end

    it "falls back to the stripped label when there is no child chat" do
      expect(helper.chat_tool_call_branch_label("Ask Mission Designer", nil)).to eq("Mission Designer")
    end

    it "falls back to the stripped label when the child chat agent has no name" do
      nameless_child_chat = Struct.new(:agent).new(Struct.new(:name).new(""))

      expect(helper.chat_tool_call_branch_label("Ask Mission Designer", nameless_child_chat)).to eq("Mission Designer")
    end

    it "formats tool call duration labels" do
      tool_call = build_stubbed(:tool_call, duration_ms: 1450)

      expect(helper.chat_tool_call_duration_label(tool_call)).to eq("1.45s")
    end

    it "formats minute and millisecond duration labels" do
      long_tool_call = build_stubbed(:tool_call, duration_ms: 65_400)
      short_tool_call = build_stubbed(:tool_call, duration_ms: 750)

      expect(helper.chat_tool_call_duration_label(long_tool_call)).to eq("1m 5.4s")
      expect(helper.chat_tool_call_duration_label(short_tool_call)).to eq("750ms")
    end

    it "returns nil for blank tool call durations" do
      expect(helper.chat_tool_call_duration_label(nil)).to be_nil
    end

    it "resolves metadata even when the tool call has no message association" do
      tool_call = build_stubbed(:tool_call, message: nil, name: "read_mission_flow", display_name: nil, icon: nil)

      expect(helper.chat_tool_call_display_name(tool_call)).to eq("Read Mission Flow")
      expect(helper.chat_tool_call_icon(tool_call)).to eq("fa-solid fa-diagram-project")
    end

    it "applies plugin presentation overrides for ask_user_questions tool calls" do
      tool_call = create(
        :tool_call,
        message: create(
          :message,
          :assistant,
          chat: create(:chat, :user_context, user: create(:user), agent: create(:agent)),
          content: nil,
        ),
        name: "ask_user_questions",
        display_name: nil,
        icon: nil,
        arguments: build_human_in_the_loop_arguments,
      )

      presentation = helper.chat_tool_call_presentation(tool_call)

      expect(presentation.display_name).to eq("Ask User Questions")
      expect(presentation.icon).to eq("fa-solid fa-circle-question")
      expect(presentation.complete_messages).to include("Waiting for your answers.")
    end

    it "hides the standard badge for ask_user_questions custom widgets" do
      tool_call = create(
        :tool_call,
        message: create(
          :message,
          :assistant,
          chat: create(:chat, :user_context, user: create(:user), agent: create(:agent)),
          content: nil,
        ),
        name: "ask_user_questions",
        display_name: "Ask User Questions",
        icon: "fa-solid fa-circle-question",
        arguments: build_human_in_the_loop_arguments,
      )

      expect(helper.chat_tool_call_badge_visible?(tool_call)).to be(false)
    end

    it "returns false for blank tool calls" do
      expect(helper.chat_tool_call_badge_visible?(nil)).to be(false)
    end

    it "defaults to visible when a tool call does not expose a badge visibility hook" do
      expect(helper.chat_tool_call_badge_visible?(Object.new)).to be(true)
    end

    it "logs and defaults to visible when badge visibility lookup raises" do
      tool_call = Object.new
      tool_call.define_singleton_method(:blank?) { false }
      tool_call.define_singleton_method(:tool_call_badge_visible?) { raise StandardError, "boom" }
      allow(Rails.logger).to receive(:error)

      expect(helper.chat_tool_call_badge_visible?(tool_call)).to be(true)
      expect(Rails.logger).to have_received(:error).with(/tool call badge visibility failed/)
    end

    it "uses the answered completion copy for completed ask_user_questions tool calls" do
      tool_call = create(
        :tool_call,
        message: create(
          :message,
          :assistant,
          chat: create(:chat, :user_context, user: create(:user), agent: create(:agent)),
          content: nil,
        ),
        name: "ask_user_questions",
        display_name: nil,
        icon: nil,
        arguments: build_answered_human_in_the_loop_arguments,
      )

      presentation = helper.chat_tool_call_presentation(tool_call)

      expect(presentation.complete_messages).to include("Answers submitted.")
    end

    it "renders plugin-owned custom tool call widgets when available", :aggregate_failures do
      user = create(:user)
      chat = create(:chat, :user_context, user:, agent: create(:agent))
      tool_call = create(
        :tool_call,
        message: create(:message, :assistant, chat:, content: nil),
        name: "ask_user_questions",
        display_name: "Ask User Questions",
        icon: "fa-solid fa-circle-question",
        arguments: build_human_in_the_loop_arguments(prompt_text: "Need one quick clarification."),
      )
      helper.singleton_class.define_method(:current_user) { user }

      html = helper.render_chat_tool_call_widget(tool_call)

      expect(html).to include("Need Your Input")
      expect(html).to include("Send")
      expect(html).to include("Which color should I use?")
      expect(html).not_to include("Human in the Loop")
      expect(html).not_to include("Question navigation")
      expect(html).to include("Your own answer")
    end

    it "returns nil when a tool call does not expose widget configuration" do
      expect(helper.render_chat_tool_call_widget(nil)).to be_nil
    end

    it "returns nil when a widget config omits the partial path" do
      tool_call = instance_double(ToolCall, tool_call_widget_render_config: { partial: "   " })

      expect(helper.render_chat_tool_call_widget(tool_call)).to be_nil
    end

    it "renders directly when a widget config does not provide a plugin view path" do
      tool_call = instance_double(
        ToolCall,
        tool_call_widget_render_config: { partial: "widgets/demo", locals: { state: "pending" }, view_path: nil },
      )

      allow(helper).to receive(:render).with(
        partial: "widgets/demo",
        locals: { state: "pending", tool_call: },
      ).and_return("rendered widget")

      expect(helper.render_chat_tool_call_widget(tool_call)).to eq("rendered widget")
    end

    it "falls back to the resolved presentation when an override raises" do
      tool_call = instance_double(
        ToolCall,
        name: "read_mission_flow",
        message: nil,
        display_name: nil,
        icon: nil,
      )
      allow(tool_call).to receive(:tool_call_presentation_override).and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      presentation = helper.chat_tool_call_presentation(tool_call)

      expect(presentation.display_name).to eq("Read Mission Flow")
      expect(Rails.logger).to have_received(:error).with(/tool call presentation override failed/)
    end

    it "logs and returns nil when widget rendering raises" do
      tool_call = instance_double(
        ToolCall,
        tool_call_widget_render_config: { partial: "widgets/demo", locals: {}, view_path: "/tmp/plugin" },
      )
      allow(helper.controller).to receive(:prepend_view_path).with("/tmp/plugin").and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      expect(helper.render_chat_tool_call_widget(tool_call)).to be_nil
      expect(Rails.logger).to have_received(:error).with(/tool call widget render failed/)
    end
  end
end
