# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::RagNavigation" do
  def response_document
    response.parsed_body
  end

  describe "admin RAG navigation" do
    let(:rag_flow) { create(:rag_flow) }

    it "avoids whole-document Turbo escapes on the RAG show page" do
      get admin_rag_flow_path(rag_flow)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-turbo-frame="_top"')
    end

    it "avoids whole-document Turbo escapes on the RAG run history page" do
      get admin_rag_flow_runs_path(rag_flow)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-turbo-frame="_top"')
    end

    it "submits nested RAG step forms through the content frame", :aggregate_failures do
      create(:rag_step, :chunking, rag_flow:, stage: "chunking")

      get edit_admin_rag_flow_step_path(rag_flow, "chunking")

      form = response_document.at_css("form#rag-step-form")

      expect(response).to have_http_status(:ok)
      expect(form).to be_present
      expect(form["data-turbo-frame"]).to eq("app-content-frame")
    end
  end
end
