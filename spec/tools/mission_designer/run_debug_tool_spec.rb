# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::RunDebugTool do
  let(:mission) do
    create(
      :mission,
      flow_data: {
        "nodes" => [
          {
            "id" => "input-node",
            "type" => "input",
            "data" => {
              "label" => "Input",
              "fields" => [
                { "variable_name" => "name", "field_type" => "string", "required" => true },
              ],
            },
          },
          {
            "id" => "output-node",
            "type" => "output",
            "data" => {
              "label" => "Output",
              "selected_variables" => ["name"],
            },
          },
        ],
        "edges" => [
          {
            "id" => "edge-1",
            "source" => "input-node",
            "sourceHandle" => "default",
            "target" => "output-node",
          },
        ],
      },
    )
  end
  let(:user) { create(:user, :admin, tenant: mission.operation.tenant) }
  let(:chat) { create(:chat, user:, mission:) }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission:,
      ui_context: nil,
      user:,
      tenant: mission.operation.tenant,
      operation: mission.operation,
    )
  end
  let(:tool) { described_class.new(mission, runtime_context:) }

  before do
    allow_any_instance_of(Missions::DebugRunner).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  describe "#name" do
    it "returns run_mission_debug" do
      expect(tool.name).to eq("run_mission_debug")
    end
  end

  describe "#execute" do
    it "requires a mission context when none is available" do
      result = described_class.new(nil, runtime_context: nil).execute(payload: { name: "Ada" }.to_json)

      expect(result).to eq(
        "Error: Create or open a mission first, or pass mission_id after creating a mission in the same turn.",
      )
    end

    it "runs the mission and returns the persisted run summary" do
      chat.messages.create!(role: :user, content: "Run this mission with {\"name\":\"Ada\"}")

      result = tool.execute(payload: { name: "Ada" }.to_json)

      run = mission.mission_runs.recent.first

      expect(run).to be_present
      expect(run).to be_completed
      expect(run.trigger_data).to eq({ "name" => "Ada" })
      expect(result).to include(
        "Debug run completed.",
        "run_id: `#{run.id}`",
        "status: completed",
        "Trigger Data",
        "Ada",
        "Execution Log",
      )
    end

    it "accepts extra debug-only variables separately from the payload" do
      chat.messages.create!(role: :user, content: "Debug the mission with the payload {\"name\":\"Ada\"}")

      tool.execute(
        payload: { name: "Ada", ignored: "value" }.to_json,
        variables: { trace_id: "debug-1" }.to_json,
      )

      run = mission.mission_runs.recent.first

      expect(run.trigger_data).to eq({ "name" => "Ada" })
      expect(run.variables["trace_id"]).to eq("debug-1")
      expect(run.variables["name"]).to eq("Ada")
    end

    it "accepts parameters and hashes without JSON strings" do
      chat.messages.create!(role: :user, content: "Run the mission with name Ada")

      tool.execute(
        payload: ActionController::Parameters.new(name: "Ada"),
        variables: { trace_id: "debug-2" },
      )

      run = mission.mission_runs.recent.first

      expect(run.trigger_data).to eq({ "name" => "Ada" })
      expect(run.variables["trace_id"]).to eq("debug-2")
    end

    it "returns full run details when requested" do
      chat.messages.create!(role: :user, content: "Execute the mission with input name=Ada")

      result = tool.execute(payload: { name: "Ada" }.to_json, detail: "full")

      expect(result).to include(
        "## Node Outputs",
        "### Step 1",
        "- input:",
        "- output:",
      )
    end

    it "does not enforce an explicit-run guard against unrelated chat wording" do
      chat.messages.create!(
        role: :user,
        content: <<~TEXT,
          Do not change the workflow itself.
          Update the mission flow later.
        TEXT
      )

      result = tool.execute(payload: { name: "Ada" }.to_json)

      expect(result).to include("Debug run completed.")
      expect(mission.mission_runs.recent.first).to be_completed
    end

    it "does not block execution when the latest user message says not to run" do
      chat.messages.create!(role: :user, content: "Do not run the mission yet")

      result = tool.execute(payload: { name: "Ada" }.to_json)

      expect(result).to include("Debug run completed.")
      expect(mission.mission_runs.recent.first).to be_completed
    end

    it "reports missing required mission inputs" do
      chat.messages.create!(role: :user, content: "Run the mission")

      result = tool.execute(payload: {}.to_json)

      expect(result).to eq("Error: Missing required mission inputs: name")
      expect(mission.mission_runs).to be_empty
    end

    it "rejects invalid payload JSON" do
      chat.messages.create!(role: :user, content: "Run the mission")

      result = tool.execute(payload: "{bad")

      expect(result).to include("Invalid JSON for payload")
      expect(mission.mission_runs).to be_empty
    end

    it "rejects non-object payload JSON" do
      chat.messages.create!(role: :user, content: "Run the mission")

      result = tool.execute(payload: "[]")

      expect(result).to include("payload must be a JSON object")
      expect(mission.mission_runs).to be_empty
    end

    it "rejects invalid variables JSON" do
      chat.messages.create!(role: :user, content: "Run the mission")

      result = tool.execute(payload: { name: "Ada" }.to_json, variables: "{bad")

      expect(result).to include("Invalid JSON for variables")
      expect(mission.mission_runs).to be_empty
    end

    it "reports failed runs explicitly" do
      failed_run = create(
        :mission_run,
        mission:,
        status: "failed",
        trigger_data: { "name" => "Ada" },
        variables: { "name" => "Ada" },
        execution_state: {},
        error: "boom",
      )
      launch = Missions::DebugRunLauncher::Result.new(
        run: failed_run,
        variables: { "name" => "Ada" },
        trigger_data: { "name" => "Ada" },
      )
      chat.messages.create!(role: :user, content: "Run the mission")
      allow(tool).to receive_messages(build_launch: launch, execute_debug_run: failed_run)

      result = tool.execute(payload: { name: "Ada" }.to_json)

      expect(result).to include("Debug run failed.", "run_id: `#{failed_run.id}`", "status: failed")
    end

    it "reports non-terminal run statuses" do
      pending_run = create(
        :mission_run,
        mission:,
        status: "pending",
        trigger_data: { "name" => "Ada" },
        variables: { "name" => "Ada" },
        execution_state: {},
      )
      launch = Missions::DebugRunLauncher::Result.new(
        run: pending_run,
        variables: { "name" => "Ada" },
        trigger_data: { "name" => "Ada" },
      )
      chat.messages.create!(role: :user, content: "Run the mission")
      allow(tool).to receive_messages(build_launch: launch, execute_debug_run: pending_run)

      result = tool.execute(payload: { name: "Ada" }.to_json)

      expect(result).to include("Debug run finished with status pending.")
    end

    it "reports unexpected execution errors" do
      launch = Missions::DebugRunLauncher::Result.new(
        run: build_stubbed(:mission_run, mission:),
        variables: { "name" => "Ada" },
        trigger_data: { "name" => "Ada" },
      )
      chat.messages.create!(role: :user, content: "Run the mission")
      allow(tool).to receive(:build_launch).and_return(launch)
      allow(tool).to receive(:execute_debug_run).and_raise(StandardError, "boom")

      result = tool.execute(payload: { name: "Ada" }.to_json)

      expect(result).to eq("Error running mission in debug mode: boom")
    end

    it "runs without chat context when called directly" do
      result = described_class.new(mission, runtime_context: nil).execute(payload: { name: "Ada" }.to_json)

      expect(result).to include("Debug run completed.")
      expect(mission.mission_runs.recent.first).to be_completed
    end

    it "refuses to run Headquarter missions" do
      headquarter_mission = create(
        :mission,
        operation: mission.operation.tenant.headquarter_operation,
        flow_data: mission.flow_data,
      )
      headquarter_chat = create(:chat, user:, mission: headquarter_mission)
      headquarter_chat.messages.create!(role: :user, content: "Run this mission")
      headquarter_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: headquarter_chat,
        mission: headquarter_mission,
        ui_context: nil,
        user:,
        tenant: mission.operation.tenant,
        operation: mission.operation.tenant.headquarter_operation,
      )

      result = described_class.new(headquarter_mission, runtime_context: headquarter_context)
                              .execute(payload: { name: "Ada" }.to_json)

      expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
      expect(headquarter_mission.mission_runs).to be_empty
    end
  end

  describe "private helpers" do
    it "builds a launcher that rejects file uploads" do
      launcher = instance_double(Missions::DebugRunLauncher, call: :ok)
      captured_resolver = nil

      allow(Missions::DebugRunLauncher).to receive(:new) do |**args|
        captured_resolver = args[:blob_url_resolver]
        launcher
      end

      result = tool.send(:build_launch, mission, trigger_data: { "name" => "Ada" }, variables: { "trace" => "1" })

      expect(Missions::DebugRunLauncher).to have_received(:new)
      expect { captured_resolver.call(nil) }
        .to raise_error(ArgumentError, "File uploads are not supported by run_mission_debug.")
      expect(result).to eq(:ok)
    end
  end
end
