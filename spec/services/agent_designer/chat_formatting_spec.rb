# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ChatFormatting do
  subject(:helper) { helper_class.new }

  let(:helper_class) do
    Class.new do
      include AgentDesigner::ChatFormatting

      public :format_cost, :format_time, :quoted, :render_value
    end
  end

  it "formats blank values and nil times" do
    expect(helper.format_cost(nil)).to eq("0.000000")
    expect(helper.format_time(nil)).to eq("-")
    expect(helper.render_value(nil, full: false)).to eq("None.")
  end

  it "renders quoted values, nonblank costs, and concrete times" do
    time = Time.utc(2026, 5, 10, 12, 30, 15)

    expect(helper.quoted("agent")).to eq("\"agent\"")
    expect(helper.format_cost(1.25)).to eq("1.250000")
    expect(helper.format_time(time)).to eq("2026-05-10T12:30:15.000Z")
  end

  it "renders string, hash, and truncated values" do
    long_text = "a" * 300

    expect(helper.render_value("plain", full: false)).to eq("plain")
    expect(helper.render_value({ "ok" => true }, full: false)).to include("\"ok\": true")
    expect(helper.render_value(long_text, full: false)).to end_with("... (truncated)")
  end
end
