# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaygroundHelper do
  describe "#playground_agents_for_select" do
    it "returns an array of [name, id] pairs" do
      agent = create(:agent, name: "Test Agent")
      result = helper.playground_agents_for_select([agent])
      expect(result).to eq([["Test Agent", agent.id]])
    end

    it "returns empty array for empty input" do
      expect(helper.playground_agents_for_select([])).to eq([])
    end
  end
end
