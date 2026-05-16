# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::AssignedRegistry do
  describe "registry lookup" do
    it "builds entries and finds them by identifier" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      agent = create(:agent, operation: skill_catalog.operation)
      agent.update!(skill_catalog_ids: [skill_catalog.id])

      registry = described_class.new(agent)
      entry = registry.find(skill.skill_identifier)

      expect(registry).to be_any
      expect(entry.skill).to eq(skill)
      expect(entry.catalog).to eq(skill_catalog)
      expect(registry.find("missing")).to be_nil
    end

    it "detects whether any assigned skills have bundled resources" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      create(:skill_resource, skill:)
      agent = create(:agent, operation: skill_catalog.operation)
      agent.update!(skill_catalog_ids: [skill_catalog.id])

      expect(described_class.new(agent).any_resources?).to be(true)
    end

    it "returns false when assigned skills have no bundled resources" do
      skill_catalog = create(:skill_catalog)
      create(:skill, skill_catalog:)
      agent = create(:agent, operation: skill_catalog.operation)
      agent.update!(skill_catalog_ids: [skill_catalog.id])

      expect(described_class.new(agent).any_resources?).to be(false)
    end
  end
end
