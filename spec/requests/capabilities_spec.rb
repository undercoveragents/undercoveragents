# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Capabilities" do
  let(:llm_connector) { create(:connector, :llm_provider, :enabled) }
  let(:agent) { create(:agent, llm_connector:) }

  let(:edit_path) do
    edit_admin_agent_capability_path(agent, :chat_title_generator)
  end

  let(:update_path) do
    admin_agent_capability_path(agent, :chat_title_generator)
  end

  describe "GET /edit" do
    it "returns ok for a draft version agent" do
      get edit_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the capability heading" do
      get edit_path
      expect(response.body).to include("Chat Title Generator")
    end

    it "does not show an availability toggle" do
      get edit_path

      document = response.parsed_body
      enabled_toggle = document.at_css('input#capability_enabled[type="checkbox"]')

      expect(enabled_toggle).to be_nil
      expect(response.body).not_to include("Availability")
    end

    context "with an unknown capability key" do
      it "responds with not found" do
        get edit_admin_agent_capability_path(agent, :nonexistent_key)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /update" do
    let(:valid_params) do
      {
        capability: {
          max_length: "50",
          max_turns: "5",
          llm_config_source: "inherit",
          temperature: "0.7",
        },
      }
    end

    it "creates a capability when it does not exist yet" do
      expect do
        patch update_path, params: valid_params
        agent.reload
      end.to change { agent.capability_enabled?(:chat_title_generator) }.from(false).to(true)
    end

    it "enables a new capability when the enabled param is omitted" do
      patch update_path, params: {
        capability: {
          max_length: "50",
          max_turns: "5",
          llm_config_source: "inherit",
          temperature: "0.7",
        },
      }

      expect(response).to redirect_to(admin_agent_path(agent))
      expect(agent.reload.capability_enabled?(:chat_title_generator)).to be(true)
    end

    it "updates existing config values" do
      agent.set_capability_config("chat_title_generator", {
                                    "max_length" => 30,
                                    "max_turns" => 3,
                                    "llm_config_source" => "inherit",
                                    "temperature" => 0.7,
                                  }, enabled: true,)
      agent.save!

      patch update_path, params: {
        capability: {
          max_length: "60",
          max_turns: "4",
          llm_config_source: "inherit",
        },
      }

      expect(agent.reload.capability(:chat_title_generator).max_length).to eq(60)
      expect(agent.capability(:chat_title_generator).max_turns).to eq(4)
    end

    it "re-renders edit for invalid values" do
      patch update_path, params: {
        capability: {
          max_length: "9999",
          max_turns: "3",
          llm_config_source: "inherit",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates configurators that do not expose _agent_record=" do
      stub_const("CapabilityWithoutAgentRecord", Class.new do
        def self.label = "Chat Title Generator"
        def self.permitted_params(raw) = raw.permit(:max_length)

        def assign_attributes(*) = nil
        def valid? = true
        def to_configuration = {}
      end,)
      allow(CapabilityPlugin).to receive(:resolve).and_call_original
      allow(CapabilityPlugin).to receive(:resolve).with(:chat_title_generator).and_return(CapabilityWithoutAgentRecord)

      patch update_path, params: { capability: { max_length: "50" } }

      expect(response).to redirect_to(admin_agent_path(agent))
    end

    it "re-renders without an availability toggle when invalid" do
      patch update_path, params: {
        capability: {
          max_length: "9999",
          max_turns: "3",
          llm_config_source: "inherit",
        },
      }

      document = response.parsed_body
      enabled_toggle = document.at_css('input#capability_enabled[type="checkbox"]')

      expect(response).to have_http_status(:unprocessable_content)
      expect(enabled_toggle).to be_nil
    end
  end

  describe "PATCH /update — memory capability (responds to after_capability_enabled)" do
    let(:memory_update_path) { admin_agent_capability_path(agent, :memory) }

    it "saves and invokes after_capability_enabled without error" do
      patch memory_update_path, params: {
        capability: {
          model_id: "text-embedding-3-small",
          embedding_dimensions: "1536",
          auto_bootstrap: "1",
        },
      }

      expect(response).to redirect_to(admin_agent_path(agent))
      expect(agent.reload.capability_enabled?(:memory)).to be(true)
    end

    it "logs an error when after_capability_enabled raises a StandardError" do
      allow_any_instance_of(Capabilities::Memory).to receive(:after_capability_enabled).and_raise(StandardError, "boom") # rubocop:disable RSpec/AnyInstance
      allow(Rails.logger).to receive(:error)

      patch memory_update_path, params: {
        capability: {
          model_id: "text-embedding-3-small",
          embedding_dimensions: "1536",
          auto_bootstrap: "1",
        },
      }

      expect(response).to redirect_to(admin_agent_path(agent))
      expect(Rails.logger).to have_received(:error).with(/after_capability_enabled failed/)
    end
  end

  describe "PATCH /update — agent save failure" do
    it "re-renders edit when agent save fails" do
      allow_any_instance_of(Agent).to receive(:save).and_return(false) # rubocop:disable RSpec/AnyInstance

      patch update_path, params: {
        capability: {
          max_length: "50",
          max_turns: "5",
          llm_config_source: "inherit",
          temperature: "0.7",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /destroy" do
    let(:destroy_path) { admin_agent_capability_path(agent, :chat_title_generator) }

    before do
      agent.set_capability_config("chat_title_generator", {
                                    "max_length" => 30,
                                    "max_turns" => 3,
                                    "llm_config_source" => "inherit",
                                    "temperature" => 0.7,
                                  }, enabled: true,)
      agent.save!
    end

    it "removes the capability" do
      delete destroy_path
      expect(agent.reload.capability_enabled?(:chat_title_generator)).to be(false)
    end

    it "redirects with a notice" do
      delete destroy_path
      expect(response).to redirect_to(admin_agent_path(agent))
      expect(flash[:notice]).to eq(I18n.t("capabilities.removed"))
    end
  end
end
