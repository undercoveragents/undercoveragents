# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatUiSupport do
  let!(:fallback_model) { create(:model, model_id: "fallback-model", provider: "openai") }
  let(:host_class) do
    Class.new do
      include ChatUiSupport

      attr_accessor :current_user
    end
  end
  let(:host) do
    host_class.new.tap do |instance|
      instance.current_user = build_stubbed(:user)
    end
  end

  describe "chat building helpers" do
    it "builds user chats without a channel and falls back to Model.first when the agent is missing" do
      chat = host.send(:build_user_chat, agent: nil, channel: nil)

      expect(chat.channel).to be_nil
      expect(chat.channel_target).to be_nil
      expect(chat.model).to eq(fallback_model)
    end

    it "falls back to the chat model for attachments when the agent model id is blank" do
      chat = build_stubbed(:chat, model: fallback_model)

      allow(chat).to receive(:agent).and_return(nil)

      expect(host.send(:chat_model_for_attachments, chat)).to eq(fallback_model)
    end

    it "uses explicit attachment signed ids without uploading new attachments" do
      chat = instance_spy(Chat)

      allow(host).to receive(:upload_chat_attachments)
      allow(host).to receive(:render_chat_status)

      host.send(:enqueue_chat_message, chat:, content: "Hello", attachment_signed_ids: ["signed-1"])

      expect(chat).to have_received(:enqueue_response!).with(
        content: "Hello",
        attachment_signed_ids: ["signed-1"],
        runtime_context: {},
      )
      expect(host).not_to have_received(:upload_chat_attachments)
      expect(host).to have_received(:render_chat_status).with(chat:)
    end
  end
end
