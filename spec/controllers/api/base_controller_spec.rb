# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::BaseController do
  controller(described_class) do
    def index
      case params[:mode]
      when "forbidden"
        send(:render_forbidden, "Access denied")
      when "not_found"
        send(:render_not_found, "Missing")
      when "unprocessable"
        send(:render_unprocessable, "Invalid")
      else
        render json: { ok: true }
      end
    end
  end

  let(:tenant) { create(:tenant, name: "API Controller Tenant") }
  let(:token_data) { ApiClient.generate_token }
  let(:api_client) do
    create(:api_client, tenant:, token_prefix: token_data[:prefix], token_digest: token_data[:digest])
  end

  before do
    routes.draw { get "index" => "api/base#index" }
  end

  def authorize!(token = token_data[:raw_token])
    api_client
    request.headers["Authorization"] = "Bearer #{token}"
  end

  describe "authentication" do
    it "renders unauthorized when the header is missing" do
      get :index

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Unauthorized")
    end

    it "renders unauthorized when the header is not a bearer token" do
      request.headers["Authorization"] = "Basic abc123"

      get :index

      expect(response).to have_http_status(:unauthorized)
    end

    it "authenticates valid bearer tokens and strips trailing whitespace" do
      authorize!("#{token_data[:raw_token]}   ")

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("ok" => true)
    end
  end

  describe "helper renderers" do
    before { authorize! }

    it "renders forbidden responses" do
      get :index, params: { mode: "forbidden" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("error" => "Forbidden", "message" => "Access denied")
    end

    it "renders not found responses" do
      get :index, params: { mode: "not_found" }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Not Found", "message" => "Missing")
    end

    it "renders unprocessable responses" do
      get :index, params: { mode: "unprocessable" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "Unprocessable Entity", "message" => "Invalid")
    end
  end
end
