# frozen_string_literal: true

require "rails_helper"

RSpec.describe CostsHelper do
  it "formats cost and percent values" do
    expect(helper.cost_currency(BigDecimal("0.123456"))).to eq("$0.123456")
    expect(helper.cost_percent(75)).to eq("75.0%")
  end

  it "renders status badges", :aggregate_failures do
    expect(helper.cost_status_badge_class("healthy")).to eq("badge-success")
    expect(helper.cost_status_icon("warning")).to eq("fa-solid fa-triangle-exclamation")
    expect(helper.cost_status_badge("exceeded")).to include("Exceeded")
  end

  it "returns option collections", :aggregate_failures do
    expect(helper.cost_period_options).to include(["This month", "month"])
    expect(helper.cost_target_type_options).to include(["Tenant", "tenant"])
    expect(helper.cost_enforcement_mode_options).to include(["Hard stop", "hard_stop"])
  end
end
