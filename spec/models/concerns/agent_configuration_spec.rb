# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentConfiguration do
  let(:dummy) do
    Object.new.tap do |object|
      object.extend(described_class)
      object.define_singleton_method(:configuration) { @configuration ||= {} }
      object.define_singleton_method(:configuration=) { |value| @configuration = value }
    end
  end

  describe "cross-model collection helpers" do
    it "resolves assigned tools without requiring operation_id" do
      tool = create(:tool, :sql_query)

      dummy.assigned_tool_ids = [tool.id]

      expect(dummy.assigned_tools).to contain_exactly(tool)
    end

    it "resolves subagents without requiring operation_id" do
      agent = create(:agent)

      dummy.subagent_ids = [agent.id]

      expect(dummy.subagents).to contain_exactly(agent)
    end

    it "resolves skill catalogs without requiring operation_id" do
      skill_catalog = create(:skill_catalog)

      dummy.skill_catalog_ids = [skill_catalog.id]

      expect(dummy.skill_catalogs).to contain_exactly(skill_catalog)
    end
  end
end
