# frozen_string_literal: true

require "rails_helper"

RSpec.describe DownloadsController, :unauthenticated do
  let(:user) { create(:user) }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("file content"), filename: "report.html", content_type: "text/html",
    )
  end

  before { sign_in(user) }

  describe "GET /dl/:id" do
    it "downloads the file by signed id" do
      get short_download_path(blob.signed_id)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("report.html")
      expect(response.headers["Content-Type"]).to include("text/html")
      expect(response.body).to eq("file content")
    end

    it "returns not found for invalid signed id" do
      get short_download_path("invalid-signed-id")

      expect(response).to have_http_status(:not_found)
    end
  end
end
