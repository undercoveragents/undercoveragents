# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::MissionTool do
  describe "tool designer metadata" do
    it "declares the editable mission tool fields" do
      expect(described_class.tool_designer_editable_attributes).to include(
        "mission_id",
        "instructions",
        "tool_widget_icon",
        "tool_widget_complete_messages",
      )
    end

    it "declares the mission tool notes" do
      expect(described_class.tool_designer_notes).to include(
        "Use list_resources(kind: \"missions\") to resolve mission_id values.",
        "The selected mission controls the runtime input and output shape for this tool.",
      )
    end

    it "declares the mission lookup hint" do
      expect(described_class.tool_designer_field_hints).to eq(
        "mission_id" => {
          "resource_kind" => "missions",
        },
      )
    end

    it "exposes the default widget presentation" do
      presentation = described_class.tool_widget_default_presentation(
        display_name: "Run Mission",
        icon: "fa-solid fa-diagram-project",
      )

      expect(presentation.running_messages).to include("Starting the mission workflow…")
      expect(presentation.complete_messages).to include("Mission run completed.")
    end
  end

  describe "mission accessor" do
    it "loads the mission by id when the cache is cold" do
      mission = create(:mission)
      mt = described_class.new(mission_id: mission.id)

      expect(mt.mission).to eq(mission)
    end

    it "returns the mission by id" do
      mission = create(:mission)
      mt = build(:tools_mission_tool, mission:)
      expect(mt.mission).to eq(mission)
    end

    it "returns nil when mission_id is blank" do
      mt = build(:tools_mission_tool, mission: nil, mission_id: nil)
      expect(mt.mission).to be_nil
    end

    it "clears mission_id when assigned nil" do
      mt = build(:tools_mission_tool)
      mt.mission = nil
      expect(mt.mission_id).to be_nil
    end

    it "re-fetches the mission when mission_id changes" do
      first_mission = create(:mission)
      second_mission = create(:mission)
      mt = build(:tools_mission_tool, mission: first_mission)

      mt.mission
      mt.mission_id = second_mission.id

      expect(mt.mission).to eq(second_mission)
    end

    it "loads the mission when the cache slot is defined but nil" do
      mission = create(:mission)
      mt = described_class.new

      mt.mission = nil
      mt.mission_id = mission.id

      expect(mt.mission).to eq(mission)
    end
  end

  describe "validations" do
    it "requires mission_id" do
      mt = build(:tools_mission_tool, mission: nil, mission_id: nil)
      expect(mt).not_to be_valid
      expect(mt.errors[:mission_id]).to include("can't be blank")
    end

    it "validates mission exists" do
      mt = build(:tools_mission_tool, mission: nil, mission_id: 999_999)
      expect(mt).not_to be_valid
      expect(mt.errors[:mission_id]).to include("must reference an existing mission")
    end

    it "is valid with a valid mission" do
      mission = create(:mission)
      mt = build(:tools_mission_tool, mission:)
      expect(mt).to be_valid
    end
  end

  describe "persistence" do
    it "#id returns the backing tool's id" do
      mt = create(:tools_mission_tool)
      expect(mt.id).to eq(mt._tool_record.id)
    end

    it "#reload refreshes attributes from the database" do
      mt = create(:tools_mission_tool)
      new_mission = create(:mission)
      new_config = mt._tool_record.configuration.merge("mission_id" => new_mission.id)
      mt._tool_record.update_column(:configuration, new_config) # rubocop:disable Rails/SkipsModelValidations
      mt.reload
      expect(mt.mission_id).to eq(new_mission.id)
    end

    it "#reload returns self when no _tool_record is set" do
      mt = build(:tools_mission_tool)
      expect(mt.reload).to be(mt)
    end

    it "== compares by id" do
      m1 = create(:tools_mission_tool)
      m2 = create(:tools_mission_tool)
      expect(m1).not_to eq(m2)
      expect(m1.reload).to eq(m1)
    end

    it "#id returns nil when no _tool_record is set" do
      mt = build(:tools_mission_tool)
      expect(mt.id).to be_nil
    end

    it "== returns false for non-MissionTool objects" do
      mt = create(:tools_mission_tool)
      expect(mt == "other").to be(false)
    end

    it "== falls through to object identity for unsaved objects" do
      m1 = build(:tools_mission_tool)
      m2 = build(:tools_mission_tool)
      expect(m1).not_to eq(m2)
      myself = m1
      expect(m1).to eq(myself)
    end
  end

  describe "#input_fields" do
    it "returns empty array when mission has no input node" do
      mt = create(:tools_mission_tool)
      expect(mt.input_fields).to eq([])
    end

    it "returns fields from mission input node" do
      mt = create(:tools_mission_tool, :with_input_fields)
      fields = mt.input_fields
      expect(fields.size).to eq(2)
      expect(fields.first["variable_name"]).to eq("username")
      expect(fields.last["variable_name"]).to eq("limit")
    end

    it "returns empty array when mission is nil" do
      mt = build(:tools_mission_tool, mission: nil, mission_id: nil)
      expect(mt.input_fields).to eq([])
    end

    it "reuses the mission input field normalization" do
      mission = create(
        :mission,
        flow_data: {
          "nodes" => [
            {
              "id" => "input-1",
              "type" => "input",
              "data" => {
                "fields" => [{ "variable_name" => "username" }].to_json,
              },
            },
          ],
          "edges" => [],
        },
      )
      mt = build(:tools_mission_tool, mission:)

      expect(mt.input_fields).to eq([{ "variable_name" => "username" }])
    end
  end

  describe "#output_variables" do
    it "returns empty array when mission has no output node" do
      mt = create(:tools_mission_tool)
      expect(mt.output_variables).to eq([])
    end

    it "returns selected variables from output node" do
      mt = create(:tools_mission_tool, :with_input_fields)
      expect(mt.output_variables).to eq(["result"])
    end

    it "returns empty array when mission is nil" do
      mt = build(:tools_mission_tool, mission: nil, mission_id: nil)
      expect(mt.output_variables).to eq([])
    end

    it "filters blank output variables through the mission accessors" do
      mission = create(
        :mission,
        flow_data: {
          "nodes" => [
            {
              "id" => "output-1",
              "type" => "output",
              "data" => {
                "selected_variables" => ["result", "", nil],
              },
            },
          ],
          "edges" => [],
        },
      )
      mt = build(:tools_mission_tool, mission:)

      expect(mt.output_variables).to eq(["result"])
    end
  end

  describe "type protocol" do
    it "returns correct type_key" do
      expect(described_class.type_key).to eq("mission_tool")
    end

    it "returns correct type_label" do
      expect(described_class.type_label).to eq("Mission")
    end

    it "returns correct type_icon" do
      expect(described_class.type_icon).to eq("fa-solid fa-diagram-project")
    end

    it ".permitted_params extracts mission_tool params" do
      params = ActionController::Parameters.new(mission_tool: { mission_id: "42" })
      result = described_class.permitted_params(params)
      expect(result.to_h).to eq({ "mission_id" => "42" })
    end

    it ".build_from_params creates an instance" do
      params = ActionController::Parameters.new(mission_tool: { mission_id: "42" })
      mt = described_class.build_from_params(params)
      expect(mt).to be_a(described_class)
      expect(mt.mission_id).to eq(42)
    end
  end

  describe "#save!" do
    it "raises when no _tool_record is set" do
      mt = build(:tools_mission_tool)
      expect { mt.save! }.to raise_error("No _tool_record set")
    end
  end

  describe "#update!" do
    it "updates attributes and persists" do
      mt = create(:tools_mission_tool)
      new_mission = create(:mission)
      mt.update!(mission_id: new_mission.id)
      mt.reload
      expect(mt.mission_id).to eq(new_mission.id)
    end
  end

  describe "#tool" do
    it "returns nil when _tool_record is not set" do
      mt = build(:tools_mission_tool)
      expect(mt.tool).to be_nil
    end

    it "returns _tool_record when set" do
      mt = create(:tools_mission_tool)
      expect(mt.tool).to eq(mt._tool_record)
    end
  end
end
