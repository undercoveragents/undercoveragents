# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rag::Runs" do
  let(:ip) { create(:rag_flow) }

  describe "GET /...runs" do
    it "returns a successful response" do
      get admin_rag_flow_runs_path(ip)
      expect(response).to have_http_status(:ok)
    end

    it "displays runs" do
      run = create(:rag_run, :completed, rag_flow: ip)
      get admin_rag_flow_runs_path(ip)
      expect(response.body).to include("##{run.id}")
    end
  end

  describe "GET /...runs/:id" do
    let(:run) { create(:rag_run, :completed, rag_flow: ip) }

    it "returns a successful response" do
      get admin_rag_flow_run_path(ip, run)
      expect(response).to have_http_status(:ok)
    end

    it "displays run details" do
      get admin_rag_flow_run_path(ip, run)
      expect(response.body).to include("Run ##{run.id}")
    end

    it "renders a turbo stream replacement for polling refreshes" do
      get admin_rag_flow_run_path(ip, run, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include("rag-run-#{run.id}")
    end

    it "renders HTML for normal show path even when turbo-stream is accepted" do
      get admin_rag_flow_run_path(ip, run), headers: {
        "ACCEPT" => "text/vnd.turbo-stream.html,text/html",
      }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Run ##{run.id}")
    end
  end

  describe "POST /...runs/:id/cancel" do
    context "with a running run" do
      let(:run) { create(:rag_run, :running, rag_flow: ip) }

      it "cancels the run" do
        post cancel_admin_rag_flow_run_path(ip, run)
        expect(run.reload).to be_cancelled
      end

      it "redirects to the run show page" do
        post cancel_admin_rag_flow_run_path(ip, run)
        expect(response).to redirect_to(admin_rag_flow_run_path(ip, run))
      end
    end

    context "with a completed run" do
      let(:run) { create(:rag_run, :completed, rag_flow: ip) }

      it "redirects with alert" do
        post cancel_admin_rag_flow_run_path(ip, run)
        expect(response).to redirect_to(admin_rag_flow_run_path(ip, run))
        expect(flash[:alert]).to be_present
      end
    end
  end
end
