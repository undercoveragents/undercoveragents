# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Telegram connector admin", :unauthenticated do
  let(:admin_user) { create(:user, :admin) }
  let(:tenant) { admin_user.tenant }

  before { sign_in(admin_user) }

  describe "POST /connectors (Telegram)" do
    let(:valid_params) do
      {
        connector_type: "telegram",
        connector: { name: "My Telegram", description: "A Telegram connector" },
        telegram: { bot_token: "123456:ABC-DEF-GHI" },
      }
    end

    it "creates a new Telegram connector" do
      expect { post admin_connectors_path, params: valid_params }
        .to change(Connector, :count).by(1)
        .and change(Connectors::Telegram, :count).by(1)
    end
  end

  describe "POST /connectors/:id/fetch_bot_info" do
    let(:telegram_connector) { create(:connector, :telegram, :enabled, tenant:) }

    it "redirects back to the connector with a notice" do
      bot_api = double("Telegram bot api", get_me: double(username: "test_bot")) # rubocop:disable RSpec/VerifiedDoubles
      allow(Telegram::Bot::Api).to receive(:new).and_return(bot_api)

      post fetch_bot_info_admin_connector_path(telegram_connector)

      expect(response).to redirect_to(admin_connector_path(telegram_connector))
      expect(flash[:notice]).to include("@test_bot")
    end

    context "when the connector is not a Telegram connector" do
      let(:sql_connector) { create(:connector, :sql_database, tenant:) }

      it "redirects with an alert" do
        post fetch_bot_info_admin_connector_path(sql_connector)

        expect(response).to redirect_to(admin_connector_path(sql_connector))
        expect(flash[:alert]).to be_present
      end
    end

    context "when fetch_bot_info! raises an error" do
      it "redirects with an error alert" do
        bot_api = double("Telegram bot api") # rubocop:disable RSpec/VerifiedDoubles
        allow(Telegram::Bot::Api).to receive(:new).and_return(bot_api)
        allow(bot_api).to receive(:get_me).and_raise(StandardError, "connection timeout")

        post fetch_bot_info_admin_connector_path(telegram_connector)

        expect(response).to redirect_to(admin_connector_path(telegram_connector))
        expect(flash[:alert]).to include("connection timeout")
      end
    end
  end
end
