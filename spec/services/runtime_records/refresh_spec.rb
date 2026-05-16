# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuntimeRecords::Refresh do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:agent_record) { create(:agent, operation:, name: "Current Agent", model_id: "gpt-4.1") }
  let(:client_channel) do
    create(:channel, :client, tenant:, default: true, name: "Preview").tap do |channel|
      create(:channel_target, channel:, target: create(:agent, operation:), default: true)
    end
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  it "refreshes when the current page shows the same record" do
    context = runtime_context_for(
      page_path: Rails.application.routes.url_helpers.admin_agent_path(agent_record),
      current_object: {
        "class_name" => "Agent",
        "id" => agent_record.id,
      },
    )

    result = described_class.broadcast!(context:, resource: "agent", record: agent_record)

    expect(result).to eq(:broadcasted)
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(
        type: "refresh",
        chat_id: chat.id,
        path: Rails.application.routes.url_helpers.admin_agent_path(agent_record),
        current_path: Rails.application.routes.url_helpers.admin_agent_path(agent_record),
      ),
    )
  end

  it "refreshes collection pages for the same resource" do
    context = runtime_context_for(page_path: "#{Rails.application.routes.url_helpers.admin_agents_path}?filter=enabled")

    result = described_class.broadcast!(context:, resource: "agent", record: agent_record, action: :delete)

    expect(result).to eq(:broadcasted)
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(
        type: "refresh",
        path: "#{Rails.application.routes.url_helpers.admin_agents_path}?filter=enabled",
        current_path: "#{Rails.application.routes.url_helpers.admin_agents_path}?filter=enabled",
      ),
    )
  end

  it "skips unrelated pages" do
    context = runtime_context_for(page_path: Rails.application.routes.url_helpers.admin_preferences_path)

    result = described_class.broadcast!(context:, resource: "agent", record: agent_record)

    expect(result).to eq(:skipped)
    expect(ActionCable.server).not_to have_received(:broadcast)
  end

  it "preserves the current channel preview path when refreshing the live preview" do
    preview_path = Rails.application.routes.url_helpers.admin_channel_path(client_channel, view: :preview, chat_id: 123)
    context = runtime_context_for(
      page_path: preview_path,
      current_object: {
        "class_name" => "Channel",
        "id" => client_channel.id,
      },
    )

    result = described_class.broadcast!(context:, resource: "channel", record: client_channel)

    expect(result).to eq(:broadcasted)
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(
        type: "refresh",
        path: preview_path,
        current_path: preview_path,
      ),
    )
  end

  it "skips non-application chats even when the page matches" do
    non_application_chat = create(:chat, user:)
    allow(non_application_chat).to receive(:application?).and_return(false)

    context = runtime_context_for(
      chat_record: non_application_chat,
      page_path: Rails.application.routes.url_helpers.admin_agent_path(agent_record),
      current_object: {
        "class_name" => "Agent",
        "id" => agent_record.id,
      },
    )

    result = described_class.broadcast!(context:, resource: "agent", record: agent_record)

    expect(result).to eq(:skipped)
    expect(ActionCable.server).not_to have_received(:broadcast)
  end

  it "skips when no chat is available" do
    context = runtime_context_for(
      chat_record: nil,
      page_path: Rails.application.routes.url_helpers.admin_agent_path(agent_record),
      current_object: {
        "class_name" => "Agent",
        "id" => agent_record.id,
      },
    )

    result = described_class.broadcast!(context:, resource: "agent", record: agent_record)

    expect(result).to eq(:skipped)
    expect(ActionCable.server).not_to have_received(:broadcast)
  end

  describe "private helpers" do
    it "maps index, create, and update page actions", :aggregate_failures do
      expect(refresh_service(page_path: agents_path, page_action: "index")
               .send(:current_page_name)).to eq("index")
      expect(refresh_service(page_path: new_agent_path, page_action: "create")
               .send(:current_page_name)).to eq("new")
      expect(
        refresh_service(
          page_path: edit_agent_path(agent_record),
          page_action: "update",
        ).send(:current_page_name),
      ).to eq("edit")
    end

    it "maps show and designer page actions", :aggregate_failures do
      expect(
        refresh_service(
          page_path: agent_show_path(agent_record),
          page_action: "show",
        ).send(:current_page_name),
      ).to eq("show")

      mission_record = create(:mission, operation:)
      expect(
        refresh_service(
          resource: "mission",
          record: mission_record,
          page_path: mission_designer_path(mission_record),
          page_action: "designer",
        ).send(:current_page_name),
      ).to eq("designer")
    end

    it "resolves canonical record paths", :aggregate_failures do
      expect(
        refresh_service(
          page_path: agent_show_path(agent_record),
          page_action: "show",
        ).send(:canonical_record_page_path),
      ).to eq(
        agent_show_path(agent_record),
      )

      mission_record = create(:mission, operation:)
      expect(
        refresh_service(
          resource: "mission",
          record: mission_record,
          page_path: mission_designer_path(mission_record),
          page_action: "designer",
        ).send(:canonical_record_page_path),
      ).to eq(
        mission_designer_path(mission_record),
      )
    end

    it "returns nil for blank and invalid canonical record pages", :aggregate_failures do
      expect(refresh_service(page_path: agent_show_path(agent_record))
               .send(:canonical_record_page_path)).to be_nil
      expect(
        refresh_service(
          page_path: agents_path,
          page_action: "show",
          record: nil,
        ).send(:canonical_record_page_path),
      ).to be_nil
    end

    it "rejects blank records and incompatible objects", :aggregate_failures do
      expect(
        refresh_service(
          page_path: agent_show_path(agent_record),
          current_object: { "class_name" => "Agent" },
          record: nil,
        ).send(:current_object_matches_record?),
      ).to be(false)
      expect(
        refresh_service(
          page_path: agent_show_path(agent_record),
          current_object: { "class_name" => "Mission", "id" => agent_record.id },
        ).send(:current_object_matches_record?),
      ).to be(false)
    end

    it "matches slug-based objects and rejects missing identifiers", :aggregate_failures do
      expect(
        refresh_service(
          page_path: agent_show_path(agent_record),
          current_object: { "class_name" => "Agent" },
        ).send(:current_object_matches_record?),
      )
        .to be(false)
      expect(
        refresh_service(
          page_path: agent_show_path(agent_record),
          current_object: { "class_name" => "Agent", "slug" => agent_record.slug },
        ).send(:current_object_matches_record?),
      ).to be(true)
    end

    it "normalizes blank and malformed paths", :aggregate_failures do
      service = refresh_service(page_path: agent_show_path(agent_record))

      expect(service.send(:normalize_path, "")).to be_nil
      expect(service.send(:normalize_path, "http://[bad")).to eq("http://[bad")
    end
  end

  def agents_path
    Rails.application.routes.url_helpers.admin_agents_path
  end

  def new_agent_path
    Rails.application.routes.url_helpers.new_admin_agent_path
  end

  def edit_agent_path(record)
    Rails.application.routes.url_helpers.edit_admin_agent_path(record)
  end

  def agent_show_path(record)
    Rails.application.routes.url_helpers.admin_agent_path(record)
  end

  def mission_designer_path(record)
    Rails.application.routes.url_helpers.designer_admin_mission_path(record)
  end

  def refresh_service(resource: "agent", record: agent_record, action: :update, **context_options)
    described_class.new(context: runtime_context_for(**context_options), resource:, record:, action:)
  end

  def runtime_context_for(page_path:, current_object: nil, page_action: nil, chat_record: chat)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: chat_record,
      mission: nil,
      ui_context: {
        "page" => { "path" => page_path, "action" => page_action }.compact,
        "current_object" => current_object,
      }.compact,
      user:,
      tenant:,
      operation:,
    )
  end
end
