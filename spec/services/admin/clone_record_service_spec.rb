# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CloneRecordService do
  describe ".call" do
    context "with an agent" do
      let(:operation) { create(:operation) }
      let(:tool) { create(:tool, :enabled, :sql_query, operation:) }
      let(:subagent) { create(:agent, operation:) }
      let(:skill_catalog) { create(:skill_catalog, operation:) }
      let!(:agent) do
        create(:agent, name: "Original Agent", operation:).tap do |record|
          record.update!(
            input_schema: [{ "variable_name" => "account_id", "field_type" => "string", "label" => "Account ID" }],
            tool_ids: [tool.id],
            subagent_ids: [subagent.id],
            skill_catalog_ids: [skill_catalog.id],
            builtin: true,
            builtin_key: "builtin-agent",
            builtin_source: "config",
          )
        end
      end

      it "clones editable metadata and clears builtin state" do
        result = described_class.call(agent)

        expect(result).to be_success
        expect(result.record).to have_attributes(
          name: "Clone of Original Agent",
          description: agent.description,
          input_schema: agent.input_schema,
          tool_ids: agent.tool_ids,
          subagent_ids: agent.subagent_ids,
          skill_catalog_ids: agent.skill_catalog_ids,
          builtin: false,
          builtin_key: nil,
          builtin_source: nil,
        )
      end
    end

    it "clones tools with a unique cloned name" do
      operation = create(:operation)
      tool = create(:tool, :enabled, :sql_query, name: "Original Tool", operation:)
      create(:tool, :sql_query, name: "Clone of Original Tool", operation:)

      result = described_class.call(tool)

      expect(result).to be_success
      expect(result.record).to have_attributes(
        name: "Clone of Original Tool (2)",
        description: tool.description,
        tool_type: tool.tool_type,
        configuration: tool.configuration,
      )
    end

    it "clones missions with flow data copied and history reset" do
      mission = create(:mission, name: "Original Mission")
      mission.update!(
        flow_data: {
          "nodes" => [{ "id" => "n1", "type" => "input" }],
          "edges" => [],
        },
        flow_undo_history: [{ "nodes" => [{ "id" => "old" }], "edges" => [] }],
        flow_redo_history: [{ "nodes" => [{ "id" => "future" }], "edges" => [] }],
      )

      result = described_class.call(mission)

      expect(result).to be_success
      expect(result.record).to have_attributes(
        name: "Clone of Original Mission",
        flow_data: mission.flow_data,
        flow_undo_history: [],
        flow_redo_history: [],
      )
    end

    it "raises for unsupported record types" do
      unsupported_record = build(:operation)

      expect do
        described_class.call(unsupported_record)
      end.to raise_error(ArgumentError, "Unsupported record type: Operation")
    end
  end
end
