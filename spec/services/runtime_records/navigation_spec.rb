# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuntimeRecords::Navigation do
  describe ".broadcast!" do
    it "broadcasts application-chat navigation payloads" do
      chat = create(:chat, :application_context, user: create(:user, :admin))
      allow(ActionCable.server).to receive(:broadcast)

      result = described_class.broadcast!(chat:, path: "/admin/missions")

      expect(result).to eq(:broadcasted)
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "navigate", chat_id: chat.id, path: "/admin/missions"),
      )
    end

    it "skips non-application or missing-user chats" do
      non_application_chat = create(:chat, :user_context, user: create(:user, :admin))
      anonymous_chat = create(:chat, :application_context, user: nil)
      allow(ActionCable.server).to receive(:broadcast)

      expect(described_class.broadcast!(chat: non_application_chat, path: "/admin/missions")).to eq(:skipped)
      expect(described_class.broadcast!(chat: anonymous_chat, path: "/admin/missions")).to eq(:skipped)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "skips when the chat is missing or the path is blank" do
      application_chat = create(:chat, :application_context, user: create(:user, :admin))
      allow(ActionCable.server).to receive(:broadcast)

      expect(described_class.broadcast!(chat: nil, path: "/admin/missions")).to eq(:skipped)
      expect(described_class.broadcast!(chat: application_chat, path: "")).to eq(:skipped)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end
  end
end
