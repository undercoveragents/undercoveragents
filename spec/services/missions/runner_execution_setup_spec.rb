# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::RunnerExecutionSetup do
  let(:runner) do
    Class.new do
      include Missions::RunnerExecutionSetup
    end.new
  end

  let(:mission_run) { instance_double(MissionRun, id: 123) }

  describe "#build_execution_context" do
    it "seeds global variables, nesting depth, and trigger data" do
      allow(runner).to receive(:normalized_flow_snapshot).with(mission_run).and_return(
        {
          "global_variables" => [
            { "key" => "max_items", "value" => "5", "type" => "number" },
          ],
        },
      )

      context = runner.send(
        :build_execution_context,
        mission_run,
        variables: { "existing" => "value" },
        trigger_data: { "topic" => "coverage" },
      )

      expect(context.get_variable("existing")).to eq("value")
      expect(context.get_variable("_nesting_depth")).to eq(0)
      expect(context.get_variable("max_items")).to eq(5)
      expect(context.get_variable("_trigger_data")).to eq({ "topic" => "coverage" })
      expect(context.get_variable("topic")).to eq("coverage")
    end
  end
end
