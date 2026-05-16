# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagFlowsHelper do
  describe "#run_status_badge" do
    it "returns success badge for completed" do
      run = build(:rag_run, :completed)
      badge = helper.run_status_badge(run)
      expect(badge).to include("badge-success")
      expect(badge).to include("Completed")
    end

    it "returns danger badge for failed" do
      run = build(:rag_run, :failed)
      badge = helper.run_status_badge(run)
      expect(badge).to include("badge-danger")
    end
  end

  describe "#run_duration" do
    it "returns formatted duration for short durations" do
      run = build(:rag_run, started_at: 5.seconds.ago, completed_at: Time.current)
      result = helper.run_duration(run)
      expect(result).to match(/\d+\.\ds/)
    end

    it "returns — for runs without started_at" do
      run = build(:rag_run, started_at: nil)
      expect(helper.run_duration(run)).to eq("—")
    end

    it "returns hours and minutes for durations >= 3600s" do
      run = build(:rag_run, started_at: 2.hours.ago, completed_at: Time.current)
      result = helper.run_duration(run)
      expect(result).to match(/\dh \dm/)
    end
  end

  describe "#run_stats_summary" do
    it "formats stats with docs and chunks" do
      run = build(:rag_run, stats: { "documents_loaded" => 10, "chunks_created" => 50 })
      result = helper.run_stats_summary(run)
      expect(result).to include("10 docs")
      expect(result).to include("50 chunks")
    end

    it "returns — for empty stats" do
      run = build(:rag_run, stats: {})
      expect(helper.run_stats_summary(run)).to eq("—")
    end

    it "includes skipped docs and embeddings when positive" do
      run = build(:rag_run, stats: { "documents_skipped" => 2, "embeddings_generated" => 100 })
      result = helper.run_stats_summary(run)
      expect(result).to include("2 skipped")
      expect(result).to include("100 embeddings")
    end
  end

  describe "#run_status_color" do
    it "returns secondary for an unrecognised status" do
      expect(helper.run_status_color("unknown")).to eq("secondary")
    end
  end

  describe "#rag_flow_status_badge" do
    it "returns Active for enabled pipeline" do
      pipeline = build(:rag_flow, enabled: true)
      badge = helper.rag_flow_status_badge(pipeline)
      expect(badge).to include("Active")
      expect(badge).to include("badge-success")
    end

    it "returns Inactive for disabled pipeline" do
      pipeline = build(:rag_flow, enabled: false)
      badge = helper.rag_flow_status_badge(pipeline)
      expect(badge).to include("Inactive")
      expect(badge).to include("badge-warning")
    end
  end

  describe "#pre_load_action_label" do
    it "returns the human-readable label" do
      expect(helper.pre_load_action_label("none")).to eq("None (append)")
      expect(helper.pre_load_action_label("truncate")).to eq("Truncate tables")
      expect(helper.pre_load_action_label("delete_matching")).to eq("Delete matching documents")
    end

    it "titleizes unknown action keys" do
      expect(helper.pre_load_action_label("custom_action")).to eq("Custom Action")
    end
  end

  describe "#step_run_status_icon_class" do
    it "returns spinner icon for running" do
      step_run = double(status: "running")
      expect(helper.step_run_status_icon_class(step_run)).to eq("fa-solid fa-spinner fa-spin")
    end

    it "returns check icon for completed" do
      step_run = double(status: "completed")
      expect(helper.step_run_status_icon_class(step_run)).to eq("fa-solid fa-check")
    end

    it "returns xmark icon for failed" do
      step_run = double(status: "failed")
      expect(helper.step_run_status_icon_class(step_run)).to eq("fa-solid fa-xmark")
    end

    it "returns forward icon for skipped" do
      step_run = double(status: "skipped")
      expect(helper.step_run_status_icon_class(step_run)).to eq("fa-solid fa-forward")
    end

    it "returns clock icon for unknown status" do
      step_run = double(status: "pending")
      expect(helper.step_run_status_icon_class(step_run)).to eq("fa-solid fa-clock")
    end
  end

  describe "#step_run_card_status_class" do
    it "returns running class for running" do
      step_run = double(status: "running")
      expect(helper.step_run_card_status_class(step_run)).to eq("rag-step-card--running")
    end

    it "returns completed class for completed" do
      step_run = double(status: "completed")
      expect(helper.step_run_card_status_class(step_run)).to eq("rag-step-card--completed")
    end

    it "returns failed class for failed" do
      step_run = double(status: "failed")
      expect(helper.step_run_card_status_class(step_run)).to eq("rag-step-card--failed")
    end

    it "returns skipped class for skipped" do
      step_run = double(status: "skipped")
      expect(helper.step_run_card_status_class(step_run)).to eq("rag-step-card--skipped")
    end

    it "returns empty string for unknown status" do
      step_run = double(status: "pending")
      expect(helper.step_run_card_status_class(step_run)).to eq("")
    end
  end
end
