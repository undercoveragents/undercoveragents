# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::Api do
  it "reports the scoped async summary and scoped predicate" do
    configurator = described_class.new(access_scope: "scoped", response_mode: "async")

    expect(configurator.summary).to eq("Scoped missions / Async")
    expect(configurator.scope_all?).to be(false)
    expect(configurator.scope_scoped?).to be(true)
  end
end
