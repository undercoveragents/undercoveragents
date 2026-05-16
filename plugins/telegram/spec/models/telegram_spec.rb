# frozen_string_literal: true

# == Schema Information
#
# Table name: connectors
# Database name: primary
#
#  id             :bigint           not null, primary key
#  configuration  :jsonb            not null
#  connector_type :string           not null
#  description    :text
#  enabled        :boolean          default(FALSE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_connectors_on_connector_type           (connector_type)
#  index_connectors_on_enabled                  (enabled)
#  index_connectors_on_name                     (name) UNIQUE
#  index_connectors_on_slug                     (slug) UNIQUE
#  index_connectors_on_telegram_webhook_secret  (((configuration ->> 'webhook_secret'::text))) UNIQUE WHERE (((connector_type)::text = 'telegram'::text) AND ((configuration ->> 'webhook_secret'::text) IS NOT NULL))
#
require "rails_helper"

RSpec.describe Connectors::Telegram do
  subject(:telegram) { build(:connectors_telegram) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:bot_token) }
  end

  describe "encryption" do
    it "encrypts bot_token" do
      tg = create(:connectors_telegram, bot_token: "123456:ABC-DEF")
      raw_value = Connector.connection.select_value(
        "SELECT configuration ->> 'bot_token' FROM connectors WHERE id = #{tg.id}",
      )
      expect(raw_value).not_to eq("123456:ABC-DEF")
      expect(tg.reload.bot_token).to eq("123456:ABC-DEF")
    end
  end

  describe "blank credential normalization" do
    it "normalizes blank webhook_secret to nil" do
      tg = build(:connectors_telegram, webhook_secret: "")
      tg.save(validate: false)
      expect(tg.webhook_secret).to be_nil
    end

    it "normalizes blank bot_token to nil (via callback)" do
      tg = build(:connectors_telegram, bot_token: "")
      tg.configurator.send(:normalize_blank_credentials)
      expect(tg.bot_token).to be_nil
    end
  end

  describe ".enabled_connector" do
    it "returns the first enabled Telegram connector" do
      tg = create(:connectors_telegram, enabled: true)
      expect(described_class.enabled_connector).to eq(tg)
    end

    it "returns nil when no enabled connector exists" do
      create(:connectors_telegram, enabled: false)
      expect(described_class.enabled_connector).to be_nil
    end
  end

  describe "#bot_api" do
    it "returns a Telegram::Bot::Api instance" do
      tg = build(:connectors_telegram, bot_token: "123:ABC")
      expect(tg.bot_api).to be_a(Telegram::Bot::Api)
    end

    it "memoizes the api instance" do
      tg = build(:connectors_telegram, bot_token: "123:ABC")
      first_call = tg.bot_api
      second_call = tg.bot_api
      expect(first_call).to be(second_call)
    end
  end

  describe "#fetch_bot_info!" do
    it "fetches bot info and saves the username" do
      tg = create(:connectors_telegram, bot_username: nil)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive(:bot_api).and_return(bot_api)
      allow(bot_api).to receive(:get_me).and_return(double(username: "my_bot"))

      tg.fetch_bot_info!
      tg.save!

      expect(tg.reload.bot_username).to eq("my_bot")
    end

    it "returns nil for unhandled VCR request errors" do
      tg = create(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: true)
      allow(bot_api).to receive(:get_me).and_raise(StandardError, "network")

      expect(tg.fetch_bot_info!).to be_nil
    end

    it "re-raises non-VCR StandardError exceptions" do
      tg = create(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: false)
      allow(bot_api).to receive(:get_me).and_raise(StandardError, "boom")

      expect { tg.fetch_bot_info! }.to raise_error(StandardError, "boom")
    end
  end

  describe "#register_webhook!" do
    it "registers a webhook with Telegram" do
      tg = create(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive(:bot_api).and_return(bot_api)
      allow(bot_api).to receive(:set_webhook)

      tg.register_webhook!("https://example.com/webhook")
      tg.save!

      expect(tg.webhook_url).to eq("https://example.com/webhook")
      expect(tg.webhook_secret).to be_present
      expect(bot_api).to have_received(:set_webhook).with(
        hash_including(url: "https://example.com/webhook"),
      )
    end

    it "returns nil for unhandled VCR request errors" do
      tg = create(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: true)
      allow(bot_api).to receive(:set_webhook).and_raise(StandardError, "network")

      expect(tg.register_webhook!("https://example.com/webhook")).to be_nil
    end

    it "re-raises non-VCR StandardErrors" do
      tg = create(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: false)
      allow(bot_api).to receive(:set_webhook).and_raise(StandardError, "fatal")

      expect { tg.register_webhook!("https://example.com/webhook") }.to raise_error(StandardError, "fatal")
    end
  end

  describe "#remove_webhook!" do
    it "removes the webhook from Telegram" do
      tg = create(:connectors_telegram, :with_webhook)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive(:bot_api).and_return(bot_api)
      allow(bot_api).to receive(:delete_webhook)

      tg.remove_webhook!

      expect(tg.webhook_url).to be_nil
      expect(tg.webhook_secret).to be_nil
      expect(bot_api).to have_received(:delete_webhook)
    end

    it "returns nil for unhandled VCR request errors" do
      tg = create(:connectors_telegram, :with_webhook)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: true)
      allow(bot_api).to receive(:delete_webhook).and_raise(StandardError, "network")

      expect(tg.remove_webhook!).to be_nil
    end

    it "re-raises non-VCR StandardErrors" do
      tg = create(:connectors_telegram, :with_webhook)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: false)
      allow(bot_api).to receive(:delete_webhook).and_raise(StandardError, "fatal")

      expect { tg.remove_webhook! }.to raise_error(StandardError, "fatal")
    end
  end

  describe "#send_message" do
    let(:tg) { build(:connectors_telegram) }
    let(:bot_api) { double("Telegram::Bot::Api") } # rubocop:disable RSpec/VerifiedDoubles

    before { allow(tg.configurator).to receive(:bot_api).and_return(bot_api) }

    it "sends a message with Markdown parse mode by default" do
      allow(bot_api).to receive(:send_message)

      tg.send_message(123, "Hello *world*")

      expect(bot_api).to have_received(:send_message).with(
        chat_id: 123,
        text: "Hello *world*",
        parse_mode: "Markdown",
      )
    end

    it "retries without parse mode when Markdown fails" do
      error = Telegram::Bot::Exceptions::ResponseError.new(
        response: double(body: '{"description":"Bad Request: can\'t parse"}'),
      )
      allow(bot_api).to receive(:send_message)
        .with(chat_id: 123, text: "bad *markdown", parse_mode: "Markdown")
        .and_raise(error)
      allow(bot_api).to receive(:send_message)
        .with(chat_id: 123, text: "bad *markdown")

      tg.send_message(123, "bad *markdown")

      expect(bot_api).to have_received(:send_message).twice
    end

    it "re-raises the error when parse_mode is not Markdown" do
      error = Telegram::Bot::Exceptions::ResponseError.new(
        response: double(body: '{"description":"Bad Request"}'),
      )
      allow(bot_api).to receive(:send_message)
        .with(chat_id: 123, text: "hello", parse_mode: "HTML")
        .and_raise(error)

      expect { tg.send_message(123, "hello", parse_mode: "HTML") }
        .to raise_error(Telegram::Bot::Exceptions::ResponseError)
    end

    it "returns nil for unhandled VCR request errors" do
      allow(bot_api).to receive(:send_message).and_raise(StandardError, "network")
      allow(tg.configurator).to receive(:vcr_unhandled_request_error?).and_return(true)

      expect(tg.send_message(123, "Hello world")).to be_nil
    end

    it "re-raises non-VCR StandardError exceptions" do
      allow(bot_api).to receive(:send_message).and_raise(StandardError, "boom")
      allow(tg.configurator).to receive(:vcr_unhandled_request_error?).and_return(false)

      expect { tg.send_message(123, "Hello world") }.to raise_error(StandardError, "boom")
    end
  end

  describe "#send_typing" do
    it "sends a typing action" do
      tg = build(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive(:bot_api).and_return(bot_api)
      allow(bot_api).to receive(:send_chat_action)

      tg.send_typing(123)

      expect(bot_api).to have_received(:send_chat_action).with(chat_id: 123, action: "typing")
    end

    it "ignores errors" do
      tg = build(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive(:bot_api).and_return(bot_api)
      allow(bot_api).to receive(:send_chat_action)
        .and_raise(Telegram::Bot::Exceptions::ResponseError.new(
                     response: double(body: '{"description":"error"}'),
                   ))

      expect { tg.send_typing(123) }.not_to raise_error
    end

    it "ignores unhandled VCR request errors" do
      tg = build(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: true)
      allow(bot_api).to receive(:send_chat_action).and_raise(StandardError, "network")

      expect { tg.send_typing(123) }.not_to raise_error
    end

    it "re-raises non-VCR StandardErrors" do
      tg = build(:connectors_telegram)
      bot_api = double("Telegram::Bot::Api") # rubocop:disable RSpec/VerifiedDoubles
      allow(tg.configurator).to receive_messages(bot_api:, vcr_unhandled_request_error?: false)
      allow(bot_api).to receive(:send_chat_action).and_raise(StandardError, "fatal")

      expect { tg.send_typing(123) }.to raise_error(StandardError, "fatal")
    end
  end

  describe "#edit_message" do
    let(:tg) { build(:connectors_telegram) }
    let(:bot_api) { double("Telegram::Bot::Api") } # rubocop:disable RSpec/VerifiedDoubles

    before { allow(tg.configurator).to receive(:bot_api).and_return(bot_api) }

    it "edits a message with Markdown parse mode by default" do
      allow(bot_api).to receive(:edit_message_text)

      tg.edit_message(123, 456, "Hello *world*")

      expect(bot_api).to have_received(:edit_message_text).with(
        chat_id: 123,
        message_id: 456,
        text: "Hello *world*",
        parse_mode: "Markdown",
      )
    end

    it "retries without parse mode when Markdown fails" do
      error = Telegram::Bot::Exceptions::ResponseError.new(
        response: double(body: '{"description":"Bad Request: can\'t parse"}'),
      )
      allow(bot_api).to receive(:edit_message_text)
        .with(chat_id: 123, message_id: 456, text: "bad *markdown", parse_mode: "Markdown")
        .and_raise(error)
      allow(bot_api).to receive(:edit_message_text)
        .with(chat_id: 123, message_id: 456, text: "bad *markdown")

      tg.edit_message(123, 456, "bad *markdown")

      expect(bot_api).to have_received(:edit_message_text).twice
    end

    it "ignores message is not modified errors" do
      error = Telegram::Bot::Exceptions::ResponseError.new(
        response: double(body: '{"description":"Bad Request: message is not modified"}'),
      )
      allow(bot_api).to receive(:edit_message_text).and_raise(error)

      expect(tg.edit_message(123, 456, "same text")).to be_nil
    end

    it "re-raises response errors when parse_mode is not Markdown" do
      error = Telegram::Bot::Exceptions::ResponseError.new(
        response: double(body: '{"description":"Bad Request: can\'t parse entities"}'),
      )
      allow(bot_api).to receive(:edit_message_text)
        .with(chat_id: 123, message_id: 456, text: "hello", parse_mode: "HTML")
        .and_raise(error)

      expect { tg.edit_message(123, 456, "hello", parse_mode: "HTML") }
        .to raise_error(Telegram::Bot::Exceptions::ResponseError)
    end
  end

  describe "#send_message_draft" do
    let(:tg) { build(:connectors_telegram) }
    let(:bot_api) { double("Telegram::Bot::Api") } # rubocop:disable RSpec/VerifiedDoubles

    before { allow(tg.configurator).to receive(:bot_api).and_return(bot_api) }

    it "calls sendMessageDraft via raw API call" do
      allow(bot_api).to receive(:call)

      tg.send_message_draft(123, 7, "draft text")

      expect(bot_api).to have_received(:call).with(
        "sendMessageDraft",
        hash_including(chat_id: 123, draft_id: 7, text: "draft text"),
      )
    end

    it "silently logs errors instead of raising" do
      allow(bot_api).to receive(:call).and_raise(StandardError, "API rate limit")
      allow(Rails.logger).to receive(:warn)

      expect { tg.send_message_draft(123, 7, "text") }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/sendMessageDraft failed/)
    end

    it "silently ignores VCR unhandled request errors without logging" do
      allow(bot_api).to receive(:call).and_raise(StandardError, "vcr error")
      allow(tg.configurator).to receive(:vcr_unhandled_request_error?).and_return(true)
      allow(Rails.logger).to receive(:warn)

      expect { tg.send_message_draft(123, 7, "text") }.not_to raise_error
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  describe "#send_document" do
    let(:tg) { build(:connectors_telegram) }
    let(:bot_api) { double("Telegram::Bot::Api") } # rubocop:disable RSpec/VerifiedDoubles
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("file content"),
        filename: "report.pdf",
        content_type: "application/pdf",
      )
    end

    before { allow(tg.configurator).to receive(:bot_api).and_return(bot_api) }

    it "sends a document to a Telegram chat" do
      allow(bot_api).to receive(:send_document)

      tg.send_document(123, blob)

      expect(bot_api).to have_received(:send_document).with(
        hash_including(chat_id: 123),
      )
    end

    it "includes a caption when provided" do
      allow(bot_api).to receive(:send_document)

      tg.send_document(123, blob, caption: "Here is your report")

      expect(bot_api).to have_received(:send_document).with(
        hash_including(chat_id: 123, caption: "Here is your report"),
      )
    end

    it "returns nil and logs on Telegram response error" do
      allow(Rails.logger).to receive(:error)
      error = Telegram::Bot::Exceptions::ResponseError.new(
        response: double(body: '{"description":"Bad Request"}'),
      )
      allow(bot_api).to receive(:send_document).and_raise(error)

      expect(tg.send_document(123, blob)).to be_nil
      expect(Rails.logger).to have_received(:error).with(/sendDocument failed/)
    end

    it "returns nil for unhandled VCR request errors" do
      allow(bot_api).to receive(:send_document).and_raise(StandardError, "network")
      allow(tg.configurator).to receive(:vcr_unhandled_request_error?).and_return(true)

      expect(tg.send_document(123, blob)).to be_nil
    end

    it "re-raises non-VCR StandardError exceptions" do
      allow(bot_api).to receive(:send_document).and_raise(StandardError, "boom")
      allow(tg.configurator).to receive(:vcr_unhandled_request_error?).and_return(false)

      expect { tg.send_document(123, blob) }.to raise_error(StandardError, "boom")
    end
  end

  describe "#to_configuration" do
    it "sets bot_token to nil when blank" do
      tg = build(:connectors_telegram, bot_token: "")
      config = tg.configurator.to_configuration
      expect(config["bot_token"]).to be_nil
    end

    it "keeps bot_token when present" do
      tg = build(:connectors_telegram, bot_token: "123:ABC")
      config = tg.configurator.to_configuration
      expect(config["bot_token"]).to eq("123:ABC")
    end
  end

  describe "#summary" do
    it "returns @ + bot_username when username is set" do
      tg = build(:connectors_telegram, bot_username: "mybot")
      expect(tg.configurator.summary).to eq("@mybot")
    end

    it "returns fallback when bot_username is blank" do
      tg = build(:connectors_telegram, bot_username: nil)
      expect(tg.configurator.summary).to eq("Telegram configured")
    end
  end

  describe "webhook_secret_uniqueness with unsaved record" do
    it "does not scope by id when connector record is not persisted" do
      tg = build(:connectors_telegram, :with_webhook, webhook_secret: "unique-secret-xyz")
      # Should be valid because no other record has the same secret
      expect(tg).to be_valid
    end

    it "handles nil _connector_record (validates without id scoping)" do
      # Call the validator directly on a raw configurator without a connector record
      configurator = described_class.new(webhook_secret: "raw-secret-xyz")
      # _connector_record is nil here; validate should not raise
      expect { configurator.valid? }.not_to raise_error
    end
  end

  describe "webhook uniqueness" do
    it "adds an error when webhook_secret is duplicated" do
      create(:connectors_telegram, :with_webhook, webhook_secret: "duplicate")
      duplicate = build(:connectors_telegram, :with_webhook, webhook_secret: "duplicate")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:webhook_secret]).to include("has already been taken")
    end
  end

  describe "private VCR helper" do
    it "returns false for non-VCR errors" do
      tg = build(:connectors_telegram)
      expect(tg.configurator.send(:vcr_unhandled_request_error?, StandardError.new("x"))).to be(false)
    end
  end

  describe ".build_from_params" do
    it "builds an instance from raw ActionController::Parameters" do
      raw = ActionController::Parameters.new(
        telegram: { bot_token: "token123" },
      )
      instance = described_class.build_from_params(raw)
      expect(instance).to be_a(described_class)
      expect(instance.bot_token).to eq("token123")
    end
  end

  describe "#show_extra_partial_name" do
    it "returns telegram_setup_card" do
      tg = build(:connectors_telegram)
      expect(tg.configurator.show_extra_partial_name).to eq("telegram_setup_card")
    end
  end

  describe "#edit_message when a VCR StandardError is raised" do
    let(:tg) { build(:connectors_telegram) }
    let(:bot_api) { double("Telegram::Bot::Api") } # rubocop:disable RSpec/VerifiedDoubles

    before { allow(tg.configurator).to receive(:bot_api).and_return(bot_api) }

    it "returns nil when StandardError is a VCR unhandled request error" do
      allow(bot_api).to receive(:edit_message_text).and_raise(StandardError, "WebMock unhandled")
      allow(tg.configurator).to receive(:vcr_unhandled_request_error?).and_return(true)

      expect(tg.edit_message(123, 456, "text")).to be_nil
    end

    it "re-raises non-VCR StandardError exceptions" do
      allow(bot_api).to receive(:edit_message_text).and_raise(StandardError, "boom")
      allow(tg.configurator).to receive(:vcr_unhandled_request_error?).and_return(false)

      expect { tg.edit_message(123, 456, "text") }.to raise_error(StandardError, "boom")
    end
  end
end
