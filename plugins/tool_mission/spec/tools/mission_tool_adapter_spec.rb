# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionToolAdapter do
  let(:mission) do
    create(
      :mission,
      flow_data: {
        "nodes" => [
          {
            "id" => "input_1",
            "type" => "input",
            "data" => {
              "fields" => [
                { "variable_name" => "username", "field_type" => "string", "required" => true },
                { "variable_name" => "limit", "field_type" => "number", "required" => false },
              ],
            },
          },
          {
            "id" => "output_1",
            "type" => "output",
            "data" => {
              "status" => "success",
              "selected_variables" => ["result"],
            },
          },
        ],
        "edges" => [],
      },
    )
  end

  let(:mission_tool) do
    create(:tools_mission_tool, mission:)
  end

  let(:tool_record) do
    mission_tool._tool_record
  end

  describe ".for_tool" do
    it "creates a tool instance for a Mission tool" do
      tool = described_class.for_tool(tool_record)
      expect(tool).to be_a(described_class)
    end

    it "raises for non-Mission tools" do
      other_tool = create(:tool, :sql_query)
      expect do
        described_class.for_tool(other_tool)
      end.to raise_error(ArgumentError, /Mission tool/)
    end
  end

  describe "#name" do
    it "derives a unique tool name from the tool record name" do
      tool = described_class.for_tool(tool_record)
      expect(tool.name).to start_with("mission_")
    end

    it "sanitizes special characters in tool names" do
      tool_record.update!(name: "My Workflow (Production) #1")
      tool = described_class.for_tool(tool_record)
      expect(tool.name).to match(/\Amission_[a-z0-9_]+\z/)
    end
  end

  describe "#description" do
    it "returns tool description when present" do
      tool_record.update!(description: "Runs the user lookup workflow")
      tool = described_class.for_tool(tool_record)
      expect(tool.description).to eq("Runs the user lookup workflow")
    end

    it "falls back to mission description" do
      mission.update!(description: "Looks up a user by username")
      tool = described_class.for_tool(tool_record)
      expect(tool.description).to eq("Looks up a user by username")
    end

    it "generates a default description when none available" do
      mission.update!(description: nil)
      tool = described_class.for_tool(tool_record)
      expect(tool.description).to include("Execute the")
    end

    it "handles nil mission gracefully" do
      tool = described_class.for_tool(tool_record)
      allow(tool_record.toolable).to receive(:mission).and_return(nil)
      expect(tool.description).to eq("Execute the mission workflow")
    end
  end

  describe "#parameters" do
    it "builds parameters from mission input fields" do
      tool = described_class.for_tool(tool_record)
      params = tool.parameters
      expect(params).to be_a(Hash)
      expect(params.keys).to contain_exactly(:username, :limit)
      expect(params[:username]).to be_a(RubyLLM::Parameter)
      expect(params[:username].required).to be(true)
      expect(params[:limit].required).to be(false)
    end

    it "provides default input parameter when no fields defined" do
      simple_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      simple_tool = create(:tools_mission_tool, mission: simple_mission)
      tool = described_class.for_tool(simple_tool._tool_record)
      params = tool.parameters
      expect(params).to be_a(Hash)
      expect(params.keys).to eq([:input])
    end

    it "skips fields with blank variable_name" do
      fields = [
        { "variable_name" => "username", "field_type" => "string", "required" => true },
        { "variable_name" => "", "field_type" => "string" },
        { "variable_name" => nil, "field_type" => "number" },
      ]
      nodes = [{ "id" => "input_1", "type" => "input", "data" => { "fields" => fields } }]
      blank_mission = create(:mission, flow_data: { "nodes" => nodes, "edges" => [] })
      blank_tool = create(:tools_mission_tool, mission: blank_mission)
      tool = described_class.for_tool(blank_tool._tool_record)
      expect(tool.parameters.keys).to eq([:username])
    end
  end

  describe "#execute" do
    it "executes the mission and returns output on success" do
      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: {
          "_output_meta" => { "status" => "success" },
          "result" => "User found: jdoe",
        },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      tool = described_class.for_tool(tool_record)
      result = tool.execute(username: "jdoe")
      expect(result).to eq({ "result" => "User found: jdoe" }.to_json)
    end

    it "returns response_body when present in output meta" do
      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: {
          "_output_meta" => { "status" => "success", "response_body" => "Custom response" },
        },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      tool = described_class.for_tool(tool_record)
      result = tool.execute(username: "jdoe")
      expect(result).to eq("Custom response")
    end

    it "returns file download link when response_body is a JSON file hash" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("<html>org</html>"), filename: "org.html", content_type: "text/html",
      )
      file_json = { filename: "org.html", blob_id: blob.id, content_type: "text/html", byte_size: 16 }.to_json
      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: { "_output_meta" => { "status" => "success", "response_body" => file_json } },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      result = described_class.for_tool(tool_record).execute(username: "jdoe")
      expect(result).to include("[📎 org.html]")
      expect(result).to include("/dl/")
    end

    it "returns file link via variable lookup when response_body is non-JSON text" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("data"), filename: "out.csv", content_type: "text/csv",
      )
      file_var = { "filename" => "out.csv", "blob_id" => blob.id, "content_type" => "text/csv", "byte_size" => 4 }
      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: {
          "_output_meta" => { "response_body" => "not valid json {" },
          "write_file.file" => file_var,
        },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      result = described_class.for_tool(tool_record).execute(username: "jdoe")
      expect(result).to include("[📎 out.csv]")
    end

    it "returns response_body as-is when JSON parses but is not a file hash" do
      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: {
          "_output_meta" => { "response_body" => '{"status":"ok","count":42}' },
        },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      result = described_class.for_tool(tool_record).execute(username: "jdoe")
      expect(result).to eq('{"status":"ok","count":42}')
    end

    it "returns error message on failure" do
      failed_run = instance_double(
        MissionRun,
        completed?: false,
        error: "Input validation failed",
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(failed_run)

      tool = described_class.for_tool(tool_record)
      result = tool.execute(username: "jdoe")
      expect(result).to include("Mission failed")
    end

    it "returns unknown error when run failed with no error message" do
      failed_run = instance_double(MissionRun, completed?: false, error: nil)

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(failed_run)

      tool = described_class.for_tool(tool_record)
      result = tool.execute(username: "jdoe")
      expect(result).to include("Unknown error")
    end

    it "handles exceptions gracefully" do
      allow(Missions::Runner).to receive(:new).and_raise(StandardError, "Connection timeout")
      allow(Rails.logger).to receive(:error)

      tool = described_class.for_tool(tool_record)
      result = tool.execute(username: "jdoe")
      expect(result).to include("Mission execution failed")
    end

    it "returns 'Mission not found' when mission is missing" do
      tool = described_class.for_tool(tool_record)
      allow(tool_record.toolable).to receive(:mission).and_return(nil)

      result = tool.execute(username: "jdoe")
      expect(result).to eq("Mission not found")
    end

    it "returns output when no selected output variables are configured" do
      no_output_mission = create(
        :mission,
        flow_data: { "nodes" => [], "edges" => [] },
      )
      no_output_tool = create(:tools_mission_tool, mission: no_output_mission)

      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: { "output" => "Direct output", "_output_meta" => {} },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(no_output_mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      tool = described_class.for_tool(no_output_tool._tool_record)
      result = tool.execute(input: "test")
      expect(result).to eq("Direct output")
    end

    it "returns output variable when present" do
      no_output_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      no_output_tool = create(:tools_mission_tool, mission: no_output_mission)

      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: { "output" => "Fallback output", "_output_meta" => {} },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(no_output_mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      tool = described_class.for_tool(no_output_tool._tool_record)
      result = tool.execute(input: "test")
      expect(result).to eq("Fallback output")
    end

    it "returns default success message when no output variables are present" do
      no_output_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      no_output_tool = create(:tools_mission_tool, mission: no_output_mission)

      completed_run = instance_double(
        MissionRun,
        completed?: true,
        variables: { "_output_meta" => {} },
      )

      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(no_output_mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      tool = described_class.for_tool(no_output_tool._tool_record)
      result = tool.execute(input: "test")
      expect(result).to eq("Mission completed successfully")
    end

    context "with file output variables" do
      let(:file_mission) do
        create(
          :mission,
          flow_data: {
            "nodes" => [
              {
                "id" => "input_1",
                "type" => "input",
                "data" => { "fields" => [{ "variable_name" => "content", "field_type" => "string" }] },
              },
              {
                "id" => "output_1",
                "type" => "output",
                "data" => { "selected_variables" => ["write_file_1.file"] },
              },
            ],
            "edges" => [],
          },
        )
      end

      let(:file_tool) { create(:tools_mission_tool, mission: file_mission) }
      let(:file_tool_record) { file_tool._tool_record }

      let(:blob) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("<html><body>Report</body></html>"),
          filename: "report.html",
          content_type: "text/html",
        )
      end

      let(:file_hash) do
        { "filename" => "report.html", "blob_id" => blob.id, "content_type" => "text/html", "byte_size" => 31 }
      end

      it "returns file as markdown download link in selected output" do
        completed_run = instance_double(
          MissionRun,
          completed?: true,
          variables: {
            "_output_meta" => { "status" => "success" },
            "write_file_1.file" => file_hash,
          },
        )

        runner = instance_double(Missions::Runner)
        allow(Missions::Runner).to receive(:new).with(file_mission).and_return(runner)
        allow(runner).to receive(:execute).and_return(completed_run)

        tool = described_class.for_tool(file_tool_record)
        result = tool.execute(content: "hello")

        expect(result).to include("[📎 report.html]")
        expect(result).to include("/dl/")
        expect(result).not_to include("blob_id")
      end

      it "formats mixed file and text outputs as readable text" do
        nodes = [{ "id" => "output_1", "type" => "output",
                   "data" => { "selected_variables" => ["write_file_1.file", "summary", "count"] }, }]
        mixed_mission = create(:mission, flow_data: { "nodes" => nodes, "edges" => [] })
        mixed_tool = create(:tools_mission_tool, mission: mixed_mission)
        vars = { "_output_meta" => {}, "write_file_1.file" => file_hash, "summary" => "Done", "count" => 42 }
        run = instance_double(MissionRun, completed?: true, variables: vars)
        runner = instance_double(Missions::Runner)
        allow(Missions::Runner).to receive(:new).with(mixed_mission).and_return(runner)
        allow(runner).to receive(:execute).and_return(run)

        result = described_class.for_tool(mixed_tool._tool_record).execute(input: "x")
        expect(result).to include("[📎 report.html]")
        expect(result).to include("summary: Done")
        expect(result).to include("count: 42")
      end

      it "returns file with markdown download link from output" do
        no_output_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
        no_output_tool = create(:tools_mission_tool, mission: no_output_mission)

        completed_run = instance_double(
          MissionRun,
          completed?: true,
          variables: { "output" => file_hash, "_output_meta" => {} },
        )

        runner = instance_double(Missions::Runner)
        allow(Missions::Runner).to receive(:new).with(no_output_mission).and_return(runner)
        allow(runner).to receive(:execute).and_return(completed_run)

        tool = described_class.for_tool(no_output_tool._tool_record)
        result = tool.execute(input: "test")

        expect(result).to include("[📎 report.html]")
        expect(result).to include("/dl/")
        expect(result).to start_with("File generated:")
      end

      it "handles missing blob in output fallback" do
        no_sel = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
        no_sel_tool = create(:tools_mission_tool, mission: no_sel)
        missing = { "filename" => "lost.pdf", "blob_id" => -1,
                    "content_type" => "application/pdf", "byte_size" => 0, }
        vars = { "output" => missing, "_output_meta" => {} }

        run = instance_double(MissionRun, completed?: true, variables: vars)
        runner = instance_double(Missions::Runner)
        allow(Missions::Runner).to receive(:new).with(no_sel).and_return(runner)
        allow(runner).to receive(:execute).and_return(run)

        result = described_class.for_tool(no_sel_tool._tool_record).execute(input: "x")
        expect(result).to eq("File generated: lost.pdf")
        expect(result).not_to include("/rails/active_storage")
      end

      it "handles missing blob gracefully in selected output" do
        missing = { "filename" => "gone.txt", "blob_id" => -1, "content_type" => "text/plain", "byte_size" => 0 }

        completed_run = instance_double(
          MissionRun,
          completed?: true,
          variables: {
            "_output_meta" => { "status" => "success" },
            "write_file_1.file" => missing,
          },
        )

        runner = instance_double(Missions::Runner)
        allow(Missions::Runner).to receive(:new).with(file_mission).and_return(runner)
        allow(runner).to receive(:execute).and_return(completed_run)

        tool = described_class.for_tool(file_tool_record)
        result = tool.execute(content: "hello")

        expect(result).to eq("File: gone.txt")
        expect(result).not_to include("/rails/active_storage")
      end

      it "enriches file arrays in output" do
        nodes = [{ "id" => "output_1", "type" => "output",
                   "data" => { "selected_variables" => ["files"] }, }]
        array_mission = create(:mission, flow_data: { "nodes" => nodes, "edges" => [] })
        array_tool = create(:tools_mission_tool, mission: array_mission)
        blob2 = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("img"), filename: "photo.png", content_type: "image/png",
        )
        file2 = { "filename" => "photo.png", "blob_id" => blob2.id,
                  "content_type" => "image/png", "byte_size" => 3, }
        vars = { "_output_meta" => {}, "files" => [file_hash, file2] }
        completed_run = instance_double(MissionRun, completed?: true, variables: vars)
        runner = instance_double(Missions::Runner)
        allow(Missions::Runner).to receive(:new).with(array_mission).and_return(runner)
        allow(runner).to receive(:execute).and_return(completed_run)

        result = described_class.for_tool(array_tool._tool_record).execute(input: "t")
        expect(result).to include("[📎 report.html]")
        expect(result).to include("[📎 photo.png]")
      end

      it "filters non-file entries from file arrays" do
        nodes = [{ "id" => "output_1", "type" => "output",
                   "data" => { "selected_variables" => ["items"] }, }]
        array_mission = create(:mission, flow_data: { "nodes" => nodes, "edges" => [] })
        array_tool = create(:tools_mission_tool, mission: array_mission)
        vars = { "_output_meta" => {}, "items" => [file_hash, "not a file", 123] }
        completed_run = instance_double(MissionRun, completed?: true, variables: vars)
        runner = instance_double(Missions::Runner)
        allow(Missions::Runner).to receive(:new).with(array_mission).and_return(runner)
        allow(runner).to receive(:execute).and_return(completed_run)

        result = described_class.for_tool(array_tool._tool_record).execute(input: "t")
        expect(result).to include("[📎 report.html]")
        expect(result).not_to include("not a file")
      end
    end
  end
end
