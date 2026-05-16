# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionControlHelper do
  describe "#mc_status_badge" do
    it "returns badge-success for completed" do
      expect(helper.mc_status_badge("completed")).to eq("badge-success")
    end

    it "returns badge-brand for running" do
      expect(helper.mc_status_badge("running")).to eq("badge-brand")
    end

    it "returns badge-secondary for pending" do
      expect(helper.mc_status_badge("pending")).to eq("badge-secondary")
    end

    it "returns badge-warning for paused" do
      expect(helper.mc_status_badge("paused")).to eq("badge-warning")
    end

    it "returns badge-danger for failed" do
      expect(helper.mc_status_badge("failed")).to eq("badge-danger")
    end

    it "returns badge-warning for cancelled" do
      expect(helper.mc_status_badge("cancelled")).to eq("badge-warning")
    end

    it "returns badge-secondary for unknown status" do
      expect(helper.mc_status_badge("unknown")).to eq("badge-secondary")
    end
  end

  describe "#mc_status_icon" do
    it "returns check icon for completed" do
      expect(helper.mc_status_icon("completed")).to eq("fa-solid fa-circle-check")
    end

    it "returns spinner for running" do
      expect(helper.mc_status_icon("running")).to eq("fa-solid fa-spinner fa-spin")
    end

    it "returns clock for pending" do
      expect(helper.mc_status_icon("pending")).to eq("fa-solid fa-clock")
    end

    it "returns xmark for failed" do
      expect(helper.mc_status_icon("failed")).to eq("fa-solid fa-circle-xmark")
    end

    it "returns pause icon for paused" do
      expect(helper.mc_status_icon("paused")).to eq("fa-solid fa-pause")
    end

    it "returns ban icon for cancelled" do
      expect(helper.mc_status_icon("cancelled")).to eq("fa-solid fa-ban")
    end

    it "returns question icon for unknown status" do
      expect(helper.mc_status_icon("unknown_status")).to eq("fa-solid fa-circle-question")
    end
  end

  describe "#mc_node_type_icon" do
    it "returns correct icons for known types" do
      expect(helper.mc_node_type_icon("agent")).to eq("fa-solid fa-user-secret")
      expect(helper.mc_node_type_icon("llm")).to eq("fa-solid fa-brain")
      expect(helper.mc_node_type_icon("condition")).to eq("fa-solid fa-code-branch")
      expect(helper.mc_node_type_icon("input")).to eq("fa-solid fa-right-to-bracket")
      expect(helper.mc_node_type_icon("output")).to eq("fa-solid fa-right-from-bracket")
    end

    it "returns cube icon for unknown types" do
      expect(helper.mc_node_type_icon("unknown")).to eq("fa-solid fa-cube")
    end
  end

  describe "#mc_node_type_color" do
    it "returns correct colors for known types" do
      expect(helper.mc_node_type_color("agent")).to eq("mc-node-agent")
      expect(helper.mc_node_type_color("llm")).to eq("mc-node-llm")
      expect(helper.mc_node_type_color("condition")).to eq("mc-node-control")
    end

    it "returns default color for unknown types" do
      expect(helper.mc_node_type_color("unknown")).to eq("mc-node-default")
    end
  end

  describe "#mc_execution_status_color" do
    it "returns correct class for success" do
      expect(helper.mc_execution_status_color(:success)).to eq("mc-exec-success")
    end

    it "returns correct class for failure" do
      expect(helper.mc_execution_status_color(:failure)).to eq("mc-exec-failure")
    end

    it "returns correct class for skip" do
      expect(helper.mc_execution_status_color(:skip)).to eq("mc-exec-skip")
    end

    it "returns default class for unknown status" do
      expect(helper.mc_execution_status_color(:unknown)).to eq("mc-exec-default")
    end
  end

  describe "#mc_format_duration" do
    it "returns dash for nil" do
      expect(helper.mc_format_duration(nil)).to eq("—")
    end

    it "returns dash for zero" do
      expect(helper.mc_format_duration(0)).to eq("—")
    end

    it "formats milliseconds" do
      expect(helper.mc_format_duration(500)).to eq("500ms")
    end

    it "formats seconds" do
      expect(helper.mc_format_duration(2500)).to eq("2.50s")
    end

    it "formats minutes" do
      expect(helper.mc_format_duration(90_000)).to eq("1m 30.0s")
    end

    it "formats float millisecond durations without fractional minute counts" do
      expect(helper.mc_format_duration(113_921.0)).to eq("1m 53.9s")
    end

    it "formats hour-long durations" do
      expect(helper.mc_format_duration(3_784_300.0)).to eq("1h 3m 4.3s")
    end
  end

  describe "#mc_format_run_duration" do
    it "returns dash when run has no duration" do
      run = instance_double(MissionRun, duration: nil)
      expect(helper.mc_format_run_duration(run)).to eq("—")
    end

    it "formats run duration" do
      run = instance_double(MissionRun, duration: 2.5)
      expect(helper.mc_format_run_duration(run)).to eq("2.50s")
    end
  end

  describe "#mc_node_label" do
    let(:flow_nodes) do
      {
        "n1" => { "id" => "n1", "data" => { "label" => "My Node" } },
        "n2" => { "id" => "n2", "data" => {} },
      }
    end

    it "returns label from flow_nodes" do
      expect(helper.mc_node_label(flow_nodes, "n1")).to eq("My Node")
    end

    it "returns node_id when node has no label" do
      expect(helper.mc_node_label(flow_nodes, "n2")).to eq("n2")
    end

    it "returns node_id when node not found" do
      expect(helper.mc_node_label(flow_nodes, "n999")).to eq("n999")
    end
  end

  describe "#mc_filter_active?" do
    it "returns false when q is blank" do
      expect(helper.mc_filter_active?({})).to be false
    end

    it "returns true when q has active filters" do
      params = { q: { status_eq: "completed" } }
      expect(helper.mc_filter_active?(params)).to be true
    end

    it "returns false when q has only sort param" do
      params = { q: { s: "id desc" } }
      expect(helper.mc_filter_active?(params)).to be false
    end
  end

  describe "#mc_node_output_preview" do
    it "returns dash for blank output" do
      expect(helper.mc_node_output_preview(nil)).to eq("—")
    end

    it "truncates long text" do
      text = "a" * 300
      result = helper.mc_node_output_preview(text)
      expect(result.length).to be <= 203
    end

    it "converts hashes to JSON" do
      result = helper.mc_node_output_preview({ "key" => "value" })
      expect(result).to include("key")
    end
  end
end
