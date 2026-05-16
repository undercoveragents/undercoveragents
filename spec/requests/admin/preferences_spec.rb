# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Preferences", :unauthenticated do
  let(:user) { create(:user, :admin) }

  before do
    create(:model, model_id: "gpt-4.1", provider: "openai")
    sign_in(user)
  end

  describe "GET /admin/preferences" do
    it "returns a successful response" do
      get admin_preferences_path
      expect(response).to have_http_status(:ok)
    end

    it "submits the save form as a top-level Turbo visit" do
      get admin_preferences_path

      expect(response.body).to include('data-turbo-frame="_top"')
    end

    it "displays the preferences title" do
      get admin_preferences_path
      expect(response.body).to include("Preferences")
    end

    it "displays the default model section" do
      get admin_preferences_path
      expect(response.body).to include("Default Model")
    end

    it "displays reasoning controls for the default model" do
      get admin_preferences_path
      expect(response.body).to include("Reasoning")
      expect(response.body).to include("Thinking Budget")
    end
  end

  describe "PATCH /admin/preferences" do
    let(:connector) { create(:connector, :llm_provider, :enabled) }

    it "updates preferences with valid params" do
      patch admin_preferences_path, params: {
        system_preference: { llm_connector_id: connector.id, model_id: "gpt-4.1" },
      }
      expect(response).to redirect_to(admin_root_path)
      pref = SystemPreference.current
      expect(pref.llm_connector_id).to eq(connector.id)
      expect(pref.model_id).to eq("gpt-4.1")
    end

    it "updates default LLM option settings" do
      patch admin_preferences_path, params: {
        system_preference: {
          llm_connector_id: connector.id,
          model_id: "gpt-4.1",
          temperature: "0.3",
          thinking_effort: "high",
          thinking_budget: "1024",
          custom_llm_params: '{"top_p":0.9}',
        },
      }

      expect(response).to redirect_to(admin_root_path)
      pref = SystemPreference.current
      expect(pref.temperature).to eq(0.3)
      expect(pref.thinking_effort).to eq("high")
      expect(pref.thinking_budget).to eq(1024)
      expect(pref.custom_llm_params).to eq({ "top_p" => 0.9 })
    end

    it "re-renders the form when custom LLM params are invalid" do
      patch admin_preferences_path, params: {
        system_preference: {
          llm_connector_id: connector.id,
          model_id: "gpt-4.1",
          custom_llm_params: "not-json",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "clears preferences when connector is blank" do
      pref = SystemPreference.current
      pref.update!(llm_connector: connector, model_id: "gpt-4.1")

      patch admin_preferences_path, params: {
        system_preference: { llm_connector_id: "" },
      }
      expect(response).to redirect_to(admin_root_path)
      pref.reload
      expect(pref.llm_connector_id).to be_nil
      expect(pref.model_id).to be_nil
    end

    it "re-renders the form with errors on invalid params" do
      patch admin_preferences_path, params: {
        system_preference: { llm_connector_id: connector.id, model_id: "" },
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates embedding preferences" do
      patch admin_preferences_path, params: {
        system_preference: { embedding_connector_id: connector.id, embedding_model_id: "text-embedding-3-small" },
      }
      expect(response).to redirect_to(admin_root_path)
      pref = SystemPreference.current
      expect(pref.embedding_connector_id).to eq(connector.id)
      expect(pref.embedding_model_id).to eq("text-embedding-3-small")
    end

    it "updates image preferences" do
      patch admin_preferences_path, params: {
        system_preference: { image_connector_id: connector.id, image_model_id: "gpt-image-1" },
      }
      expect(response).to redirect_to(admin_root_path)
      pref = SystemPreference.current
      expect(pref.image_connector_id).to eq(connector.id)
      expect(pref.image_model_id).to eq("gpt-image-1")
    end

    it "clears embedding preferences when connector is blank" do
      pref = SystemPreference.current
      pref.update!(embedding_connector: connector, embedding_model_id: "text-embedding-3-small")

      patch admin_preferences_path, params: {
        system_preference: { embedding_connector_id: "" },
      }
      expect(response).to redirect_to(admin_root_path)
      pref.reload
      expect(pref.embedding_connector_id).to be_nil
      expect(pref.embedding_model_id).to be_nil
    end

    it "clears image preferences when connector is blank" do
      pref = SystemPreference.current
      pref.update!(image_connector: connector, image_model_id: "gpt-image-1")

      patch admin_preferences_path, params: {
        system_preference: { image_connector_id: "" },
      }
      expect(response).to redirect_to(admin_root_path)
      pref.reload
      expect(pref.image_connector_id).to be_nil
      expect(pref.image_model_id).to be_nil
    end
  end
end
