# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::AggregateQuery do
  it "ignores unknown dimensions" do
    message = create(:message)

    result = described_class.new(Message.where(id: message.id)).by_dimension("unknown")

    expect(result).to be_empty
  end
end
