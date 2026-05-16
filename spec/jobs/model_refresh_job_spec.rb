# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModelRefreshJob do
  it "calls Model.refresh!" do
    allow(Model).to receive(:refresh!)

    described_class.perform_now

    expect(Model).to have_received(:refresh!)
  end
end
