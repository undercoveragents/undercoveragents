# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::GenerateImage do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns generate_image" do
      expect(described_class.node_type).to eq("generate_image")
    end
  end

  describe ".node_category" do
    it "returns llm" do
      expect(described_class.node_category).to eq(:llm)
    end
  end

  describe ".required_field_keys" do
    it "requires connector_id and model" do
      expect(described_class.required_field_keys).to eq(["connector_id", "model"])
    end
  end

  describe ".variable_schema" do
    it "declares image and revised_prompt outputs" do
      schema = described_class.variable_schema
      expect(schema.outputs.map(&:name)).to include("image", "revised_prompt")
    end
  end

  describe ".extract_variables" do
    it "extracts template variables from prompt" do
      variables = []
      seen = Set.new
      described_class.extract_variables({ "prompt" => "Draw {{subject}} in {{style}}" }, "Image", variables, seen)
      expect(variables.pluck(:key)).to contain_exactly("subject", "style")
    end
  end

  describe ".designer_instructions" do
    it "returns non-empty instructions" do
      expect(described_class.designer_instructions).to include("generate_image")
    end
  end

  describe "#execute" do
    it "fails when connector is not configured" do
      context.set_variable("_current_node_data", { "connector_id" => nil })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("LLM connector not configured")
    end

    it "fails when model is blank" do
      connector = create(:connector, :llm_provider, enabled: true)
      context.set_variable("_current_node_data", { "connector_id" => connector.id.to_s, "model" => "" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("LLM model not configured")
    end

    it "fails when prompt is blank and no input" do
      connector = create(:connector, :llm_provider, enabled: true)
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "dall-e-3",
                             "prompt" => "",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("no prompt")
    end

    it "generates image and stores in active storage" do
      connector = create(:connector, :llm_provider, enabled: true)
      create(:model, model_id: "dall-e-3", provider: "openai")
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "dall-e-3",
                             "prompt" => "A red panda coding Ruby",
                             "label" => "test_image",
                           })

      fake_image = double( # rubocop:disable RSpec/VerifiedDoubles
        "image",
        to_blob: "fake-image-data",
        mime_type: "image/png",
        revised_prompt: "A cute red panda",
      )
      llm_context = double("context") # rubocop:disable RSpec/VerifiedDoubles
      allow(llm_context).to receive(:paint).and_return(fake_image)
      allow(connector).to receive(:build_context).and_return(llm_context)
      allow(ConnectorLookup).to receive(:find)
        .with(connector.id.to_s, tenant: run.mission.operation.tenant)
        .and_return(connector)
      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["image"]).to include("filename", "blob_id", "content_type", "byte_size")
      expect(result.variables["revised_prompt"]).to eq("A cute red panda")
    end

    it "returns failure on image generation error" do
      connector = create(:connector, :llm_provider, enabled: true)
      create(:model, model_id: "dall-e-3", provider: "openai")
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "dall-e-3",
                             "prompt" => "Test prompt",
                           })

      llm_context = double("context") # rubocop:disable RSpec/VerifiedDoubles
      allow(llm_context).to receive(:paint).and_raise(StandardError, "Content policy violation")
      allow(connector).to receive(:build_context).and_return(llm_context)
      allow(ConnectorLookup).to receive(:find)
        .with(connector.id.to_s, tenant: run.mission.operation.tenant)
        .and_return(connector)
      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Image generation error")
    end

    it "omits revised_prompt when not present" do
      connector = create(:connector, :llm_provider, enabled: true)
      create(:model, model_id: "dall-e-3", provider: "openai")
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "dall-e-3",
                             "prompt" => "A test image",
                             "label" => "test",
                           })

      fake_image = double("image", to_blob: "data", mime_type: "image/png", revised_prompt: nil) # rubocop:disable RSpec/VerifiedDoubles
      llm_context = double("context") # rubocop:disable RSpec/VerifiedDoubles
      allow(llm_context).to receive(:paint).and_return(fake_image)
      allow(connector).to receive(:build_context).and_return(llm_context)
      allow(ConnectorLookup).to receive(:find)
        .with(connector.id.to_s, tenant: run.mission.operation.tenant)
        .and_return(connector)
      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables).not_to have_key("revised_prompt")
    end

    it "passes size option when configured" do
      connector = create(:connector, :llm_provider, enabled: true)
      create(:model, model_id: "dall-e-3", provider: "openai")
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "dall-e-3",
                             "prompt" => "Wide landscape",
                             "size" => "1792x1024",
                             "label" => "wide",
                           })

      fake_image = double("image", to_blob: "data", mime_type: "image/png", revised_prompt: nil) # rubocop:disable RSpec/VerifiedDoubles
      llm_context = double("context") # rubocop:disable RSpec/VerifiedDoubles
      allow(llm_context).to receive(:paint).and_return(fake_image)
      allow(connector).to receive(:build_context).and_return(llm_context)
      allow(ConnectorLookup).to receive(:find)
        .with(connector.id.to_s, tenant: run.mission.operation.tenant)
        .and_return(connector)
      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance

      result = node.execute(context)

      expect(result).to be_success
      expect(llm_context).to have_received(:paint).with("Wide landscape", model: "dall-e-3", size: "1792x1024")
    end
  end

  describe "#resolve_connector" do
    it "returns nil when context is nil" do
      expect(node.send(:resolve_connector, { "connector_id" => "1" }, context: nil)).to be_nil
    end

    it "returns nil when the mission run is missing" do
      blank_context = instance_double(Missions::ExecutionContext, mission_run: nil)

      expect(node.send(:resolve_connector, { "connector_id" => "1" }, context: blank_context)).to be_nil
    end

    it "returns nil when the mission has no operation" do
      mission = instance_double(Mission, operation: nil)
      mission_run = instance_double(MissionRun, mission:)
      blank_context = instance_double(Missions::ExecutionContext, mission_run:)

      expect(node.send(:resolve_connector, { "connector_id" => "1" }, context: blank_context)).to be_nil
    end
  end
end
