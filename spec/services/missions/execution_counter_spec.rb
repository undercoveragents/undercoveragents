# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::ExecutionCounter do
  it "increments from zero" do
    counter = described_class.new

    expect { counter.increment }
      .to change(counter, :value).from(0).to(1)
  end

  it "supports repeated increments" do
    counter = described_class.new

    3.times { counter.increment }

    expect(counter.value).to eq(3)
  end
end
