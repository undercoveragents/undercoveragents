# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Models" do
  def rendered_model_rows_text
    response.parsed_body.css(".models-tr").map { |row| row.text.squish }.join(" ")
  end

  describe "GET /admin/models" do
    it "renders the models index" do
      create(:model, provider: "openai", model_id: "gpt-4.1", name: "GPT-4.1")

      get admin_models_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Models")
      expect(response.body).to include("GPT-4.1")
    end

    it "shows the empty state when there are no models" do
      get admin_models_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No models found")
    end

    it "filters by search query" do
      create(:model, provider: "openai", model_id: "gpt-4.1", name: "GPT-4.1")
      create(:model, provider: "anthropic", model_id: "claude-3.7", name: "Claude 3.7")

      get admin_models_path, params: { search: "claude" }

      expect(rendered_model_rows_text).to include("Claude 3.7")
      expect(rendered_model_rows_text).not_to include("GPT-4.1")
    end

    it "filters by provider" do
      create(:model, provider: "openai", model_id: "gpt-4.1")
      create(:model, provider: "anthropic", model_id: "claude-3.7")

      get admin_models_path, params: { provider: "anthropic" }

      expect(rendered_model_rows_text).to include("claude-3.7")
      expect(rendered_model_rows_text).not_to include("gpt-4.1")
    end

    it "filters by capability from the json array" do
      create(:model, model_id: "vision-model", capabilities: ["vision", "streaming"])
      create(:model, model_id: "text-model", capabilities: ["streaming"])

      get admin_models_path, params: { capability: "vision" }

      expect(rendered_model_rows_text).to include("vision-model")
      expect(rendered_model_rows_text).not_to include("text-model")
    end

    it "filters by input modality from the json object" do
      create(:model, model_id: "audio-in", modalities: { "input" => ["audio"], "output" => ["text"] })
      create(:model, model_id: "text-in", modalities: { "input" => ["text"], "output" => ["text"] })

      get admin_models_path, params: { input_modality: "audio" }

      expect(rendered_model_rows_text).to include("audio-in")
      expect(rendered_model_rows_text).not_to include("text-in")
    end

    it "filters by output modality from the json object" do
      create(:model, model_id: "embed-out", modalities: { "input" => ["text"], "output" => ["embeddings"] })
      create(:model, model_id: "text-out", modalities: { "input" => ["text"], "output" => ["text"] })

      get admin_models_path, params: { output_modality: "embeddings" }

      expect(rendered_model_rows_text).to include("embed-out")
      expect(rendered_model_rows_text).not_to include("text-out")
    end

    it "shows metadata badges for input and capabilities" do
      create(
        :model,
        model_id: "priced-model",
        modalities: { "input" => ["text", "image"], "output" => ["text"] },
        capabilities: ["streaming", "vision"],
      )

      get admin_models_path

      expect(response.body).to include("models-badge-row")
      expect(response.body).to include("text")
      expect(response.body).to include("image")
      expect(response.body).to include("vision")
    end

    it "renders family after the model id column content" do
      create(:model, model_id: "gpt-4.1", family: "gpt")

      get admin_models_path

      expect(response.body.index("gpt-4.1")).to be < response.body.rindex("gpt")
    end

    it "shows pricing columns from the pricing json" do
      create(
        :model,
        model_id: "priced-model",
        pricing: {
          "text_tokens" => {
            "standard" => {
              "input_per_million" => "1.25",
              "output_per_million" => "9.50",
              "cached_input_per_million" => "0.40",
            },
          },
        },
      )

      get admin_models_path

      expect(response.body).to include("$1.25")
      expect(response.body).to include("$9.50")
      expect(response.body).to include("$0.40")
    end

    it "sorts by meaningful columns" do
      create(:model, model_id: "smaller", name: "Smaller", context_window: 8_000)
      create(:model, model_id: "larger", name: "Larger", context_window: 200_000)

      get admin_models_path, params: { sort: "context_window", direction: "desc" }

      expect(response.body.index("larger")).to be < response.body.index("smaller")
    end

    it "falls back to a safe default sort for unsupported columns" do
      create(:model, provider: "openai", model_id: "gpt-4.1")

      get admin_models_path, params: { sort: "unsupported", direction: "sideways" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("gpt-4.1")
    end

    it "paginates the table" do
      55.times do |index|
        create(:model, provider: "openai", model_id: format("model-%03d", index), name: "Model #{index}")
      end

      get admin_models_path, params: { page: 2 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("model-050")
      expect(response.body).not_to include("model-000")
    end
  end

  describe "POST /admin/models/refresh" do
    it "enqueues ModelRefreshJob and redirects" do
      post refresh_admin_models_path

      expect(response).to redirect_to(admin_models_path)
      follow_redirect!
      expect(response.body).to include("Model refresh started")
    end

    it "enqueues the job" do
      expect { post refresh_admin_models_path }.to have_enqueued_job(ModelRefreshJob)
    end
  end
end
