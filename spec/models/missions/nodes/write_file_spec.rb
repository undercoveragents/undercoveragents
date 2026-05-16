# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::WriteFile do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns write_file" do
      expect(described_class.node_type).to eq("write_file")
    end
  end

  describe ".node_category" do
    it "is node" do
      expect(described_class.node_category).to eq(:node)
    end
  end

  describe ".required_field_keys" do
    it "requires filename and content" do
      expect(described_class.required_field_keys).to eq(["filename", "content"])
    end
  end

  describe ".variable_schema" do
    it "declares file output" do
      schema = described_class.variable_schema
      expect(schema.outputs.map(&:name)).to include("file")
    end

    it "does not declare runtime inputs" do
      expect(described_class.variable_schema.inputs).to be_empty
    end
  end

  describe ".input_schema" do
    it "declares filename and content config inputs" do
      expect(described_class.input_schema.pluck(:name)).to contain_exactly("filename", "content")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe ".designer_instructions" do
    it "includes write_file type reference" do
      expect(described_class.designer_instructions).to include("write_file")
    end
  end

  describe ".extract_variables" do
    it "extracts template variables from content and filename" do
      data = { "filename" => "report_{{date}}.html", "content" => "Hello {{name}}" }
      variables = []
      seen = Set.new

      described_class.extract_variables(data, "Write File", variables, seen)

      expect(seen).to include("date", "name")
    end
  end

  describe "#execute" do
    it "creates a file with static content" do
      context.set_variable("_current_node_data", {
                             "filename" => "test.txt",
                             "content" => "Hello, World!",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["file"]).to include(
        "filename" => "test.txt",
        "content_type" => "text/plain",
      )
      expect(result.variables["file"]["blob_id"]).to be_present
      expect(result.variables["file"]["byte_size"]).to eq(13)
    end

    it "attaches file to the mission run" do
      context.set_variable("_current_node_data", {
                             "filename" => "output.html",
                             "content" => "<h1>Report</h1>",
                           })

      expect { node.execute(context) }.to change { run.files.count }.by(1)
    end

    it "interpolates variables in filename" do
      context.set_variable("date", "2025-01-01")
      context.set_variable("_current_node_data", {
                             "filename" => "report_{{date}}.txt",
                             "content" => "content",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["file"]["filename"]).to eq("report_2025-01-01.txt")
    end

    it "interpolates variables in content" do
      context.set_variable("name", "Alice")
      context.set_variable("_current_node_data", {
                             "filename" => "greeting.txt",
                             "content" => "Hello {{name}}!",
                           })

      result = node.execute(context)

      expect(result).to be_success
      blob = ActiveStorage::Blob.find(result.variables["file"]["blob_id"])
      expect(blob.download).to eq("Hello Alice!")
    end

    it "fails with blank filename" do
      context.set_variable("_current_node_data", {
                             "filename" => "",
                             "content" => "some content",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Filename is required")
    end

    it "fails with blank content" do
      context.set_variable("_current_node_data", {
                             "filename" => "test.txt",
                             "content" => "",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Content is required")
    end

    it "detects content type from filename extension" do
      context.set_variable("_current_node_data", {
                             "filename" => "report.html",
                             "content" => "<h1>Hello</h1>",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["file"]["content_type"]).to eq("text/html")
    end

    it "outputs file metadata as node output" do
      context.set_variable("_current_node_data", {
                             "filename" => "data.json",
                             "content" => '{"key": "value"}',
                           })

      result = node.execute(context)

      expect(result.output).to include("filename" => "data.json")
      expect(result.output).to include("blob_id", "content_type", "byte_size")
    end
  end
end
