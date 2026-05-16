# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientChatPathsHelper do
  let(:agent) { create(:agent, enabled: true) }
  let(:channel) { create(:channel, :client, default: true, tenant: agent.tenant) }
  let(:chat) { create(:chat, :user_context, agent:, channel:) }

  before do
    current_client = channel
    helper.define_singleton_method(:current_client_record) { current_client }
  end

  describe "preview-aware paths" do
    let(:actual_paths) do
      {
        preview_page_without_client: helper.admin_client_preview_page_path(client: nil),
        brand_url: helper.client_chat_brand_url,
        new_path: helper.client_chat_new_path,
        sidebar_link_path: helper.client_chat_sidebar_link_path(chat),
        sidebar_link_data: helper.client_chat_sidebar_link_data,
        delete_path: helper.client_chat_delete_path(chat),
        more_path: helper.client_chat_more_path(page: 2),
        message_path: helper.client_chat_message_path(chat),
        cancel_path: helper.client_chat_cancel_path(chat),
        poll_path: helper.client_chat_poll_path(chat),
      }
    end

    let(:expected_paths) do
      {
        preview_page_without_client: root_path,
        brand_url: admin_channel_path(channel, view: :preview),
        new_path: chats_path(preview_channel_id: channel.to_param, admin_preview: true),
        sidebar_link_path: admin_channel_path(channel, view: :preview, chat_id: chat.id),
        sidebar_link_data: { turbo_frame: "app-content-frame" },
        delete_path: chat_path(chat, preview_channel_id: channel.to_param, admin_preview: true),
        more_path: more_chats_path(
          page: 2,
          format: :turbo_stream,
          preview_channel_id: channel.to_param,
          admin_preview: true,
        ),
        message_path: chat_messages_path(chat, preview_channel_id: channel.to_param, admin_preview: true),
        cancel_path: cancel_chat_path(chat, preview_channel_id: channel.to_param, admin_preview: true),
        poll_path: chat_path(chat, format: :turbo_stream, preview_channel_id: channel.to_param, admin_preview: true),
      }
    end

    before do
      helper.define_singleton_method(:admin_client_preview?) { true }
    end

    it "builds preview-aware chat paths" do
      expect(actual_paths).to eq(expected_paths)
    end

    it "returns passthrough extras when preview params are built without a client" do
      params = helper.send(:client_chat_preview_params, client: nil, extra: { page: 3, format: :turbo_stream })

      expect(params).to eq(page: 3, format: :turbo_stream)
    end
  end

  describe "standard chat paths" do
    let(:actual_paths) do
      {
        brand_url: helper.client_chat_brand_url,
        new_path: helper.client_chat_new_path,
        sidebar_link_path: helper.client_chat_sidebar_link_path(chat),
        sidebar_link_data: helper.client_chat_sidebar_link_data,
        delete_path: helper.client_chat_delete_path(chat),
        more_path: helper.client_chat_more_path(page: 2),
        message_path: helper.client_chat_message_path(chat),
        cancel_path: helper.client_chat_cancel_path(chat),
        poll_path: helper.client_chat_poll_path(chat),
      }
    end

    let(:expected_paths) do
      {
        brand_url: root_path,
        new_path: chats_path,
        sidebar_link_path: chat_path(chat),
        sidebar_link_data: {},
        delete_path: chat_path(chat),
        more_path: more_chats_path(page: 2, format: :turbo_stream),
        message_path: chat_messages_path(chat),
        cancel_path: cancel_chat_path(chat),
        poll_path: chat_path(chat, format: :turbo_stream),
      }
    end

    before do
      helper.define_singleton_method(:admin_client_preview?) { false }
    end

    it "falls back to the shared client chat routes" do
      expect(actual_paths).to eq(expected_paths)
    end
  end
end
