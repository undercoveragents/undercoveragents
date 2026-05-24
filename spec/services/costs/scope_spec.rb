# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::Scope do
  it "returns no messages for unsupported limit target types" do
    tenant = create(:tenant).tap(&:ensure_core_resources!)
    limit = build(:cost_limit, tenant:, target_type: "unknown")
    scope = described_class.new(tenant:)

    result = scope.send(:apply_limit_target, Message.all, limit)

    expect(result).to be_empty
  end
end
