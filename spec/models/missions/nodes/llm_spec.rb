# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Llm do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  def llm_node_data(connector:, model:, prompt:, **extra)
    {
      "connector_id" => connector.id.to_s,
      "model" => model,
      "prompt" => prompt,
      **extra.transform_keys(&:to_s),
    }
  end

  def stub_shared_llm_chat(connector:, chat:, response:)
    allow(connector).to receive(:build_context).and_return(double)
    allow(chat).to receive(:context=)
    allow(chat).to receive(:with_instructions)
    allow(chat).to receive(:with_tools)
    allow(chat).to receive(:ask).and_return(response)
    allow(Chat).to receive(:create!).and_return(chat)
    allow(Llm::ChatOptions).to receive(:apply_to_chat)
  end

  def configure_shared_llm_node(context, connector, model_record)
    context.set_variable(
      "_current_node_data",
      llm_node_data(
        connector:,
        model: model_record.model_id,
        prompt: "Summarize this",
        temperature: 0.4,
        thinking_effort: "high",
        thinking_budget: 128,
        custom_llm_params: '{"top_p":0.9}',
      ),
    )
  end

  def configure_shared_llm_node_with_tools(context, connector, model_record, tool_ids)
    context.set_variable(
      "_current_node_data",
      llm_node_data(connector:, model: model_record.model_id, prompt: "Summarize this", tool_ids:),
    )
  end

  def create_enabled_mission_tool_for(operation)
    mission_tool = create(:tools_mission_tool, mission: create(:mission, operation:))
    mission_tool._tool_record.update!(operation:, enabled: true)
    mission_tool._tool_record
  end

  def expect_shared_llm_options(chat, model_record)
    expect(Llm::ChatOptions).to have_received(:apply_to_chat).with(
      chat:,
      model_id: model_record.model_id,
      model_record:,
      tools_present: false,
      temperature: 0.4,
      thinking_effort: "high",
      thinking_budget: 128,
      custom_params: '{"top_p":0.9}',
    )
  end

  describe ".required_field_keys" do
    it "has no unconditional required fields" do
      expect(described_class.required_field_keys).to eq([])
    end
  end

  describe ".json_field_keys" do
    it "marks custom_llm_params as JSON-backed" do
      expect(described_class.json_field_keys).to eq(["custom_llm_params"])
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

    it "routes temperature, thinking, and custom params through shared chat options" do
      connector = create(:connector, :llm_provider, enabled: true)
      model_record = create(:model, model_id: "gpt-4.1", provider: connector.provider,
                                    capabilities: ["temperature", "reasoning"],)
      response = double("response", content: "Generated response") # rubocop:disable RSpec/VerifiedDoubles
      chat = instance_double(Chat)

      stub_shared_llm_chat(connector:, chat:, response:)
      configure_shared_llm_node(context, connector, model_record)

      result = node.execute(context)

      expect(result).to be_success
      expect_shared_llm_options(chat, model_record)
    end

    it "registers selected tools from the mission operation on the chat" do
      connector = create(:connector, :llm_provider, enabled: true)
      model_record = create(:model, model_id: "gpt-4.1", provider: connector.provider)
      tool_record = create_enabled_mission_tool_for(run.mission.operation)
      response = double("response", content: "Generated response") # rubocop:disable RSpec/VerifiedDoubles
      chat = instance_double(Chat)

      stub_shared_llm_chat(connector:, chat:, response:)
      configure_shared_llm_node_with_tools(context, connector, model_record, [tool_record.id])

      result = node.execute(context)

      expect(result).to be_success
      expect(chat).to have_received(:with_tools) do |*tools|
        expect(tools.size).to eq(1)
        expect(tools.first).to be_a(MissionToolAdapter)
      end
    end

    it "resolves the current branch input when available" do
      connector = create(:connector, :llm_provider, enabled: true)
      create(:model, model_id: "gpt-4.1", provider: "openai")
      context.set_variable("_current_node_data", llm_node_data(connector:, model: "gpt-4.1", prompt: "Summarize"))
      context.current_input = "Hello from branch input"

      response = double("response", content: "Summary result") # rubocop:disable RSpec/VerifiedDoubles
      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Chat).to receive(:ask).and_return(response) # rubocop:disable RSpec/AnyInstance

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["response"]).to eq("Summary result")
    end

    it "falls back to input variable when the current branch input is nil" do
      connector = create(:connector, :llm_provider, enabled: true)
      create(:model, model_id: "gpt-4.1", provider: "openai")
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "gpt-4.1",
                             "prompt" => "Process this",
                           })
      context.set_variable("input", "Hello from input")

      response = double("response", content: "Processed") # rubocop:disable RSpec/VerifiedDoubles
      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Chat).to receive(:ask).and_return(response) # rubocop:disable RSpec/AnyInstance

      result = node.execute(context)

      expect(result).to be_success
    end

    it "fails when there is no prompt and no input" do
      connector = create(:connector, :llm_provider, enabled: true)
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "gpt-4.1",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("no prompt and no input")
    end

    it "returns failure on LLM error" do
      connector = create(:connector, :llm_provider, enabled: true)
      create(:model, model_id: "gpt-4.1", provider: "openai")
      context.set_variable("_current_node_data", {
                             "connector_id" => connector.id.to_s,
                             "model" => "gpt-4.1",
                             "prompt" => "Hello",
                           })

      allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Chat).to receive(:ask).and_raise(StandardError, "API timeout") # rubocop:disable RSpec/AnyInstance

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("LLM error")
    end

    context "with file attachments" do
      let(:connector) { create(:connector, :llm_provider, enabled: true) }
      let(:blob) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("file content"), filename: "doc.txt", content_type: "text/plain",
        )
      end

      before do
        create(:model, model_id: "gpt-4.1", provider: "openai")
        allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object) # rubocop:disable RSpec/AnyInstance
      end

      it "passes file attachments from configured file_variables" do
        file_meta = { "blob_id" => blob.id, "filename" => "doc.txt" }
        context.set_node_variables("input_1", { "document" => file_meta })
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s,
                               "model" => "gpt-4.1",
                               "prompt" => "Analyze this document",
                               "file_variables" => ["input_1.document"],
                             })
        context.current_input = "Please review"

        response = double("response", content: "Analysis result") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask) do |_chat, _msg, **opts| # rubocop:disable RSpec/AnyInstance
          expect(opts[:with]).to be_a(String)
          response
        end

        result = node.execute(context)

        expect(result).to be_success
        expect(result.variables["response"]).to eq("Analysis result")
      end

      it "auto-detects file from the current branch input" do
        file_meta = { "blob_id" => blob.id, "filename" => "image.png" }
        context.current_input = file_meta
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s,
                               "model" => "gpt-4.1",
                               "prompt" => "Describe this image",
                             })

        response = double("response", content: "It is an image") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask).and_return(response) # rubocop:disable RSpec/AnyInstance

        result = node.execute(context)

        expect(result).to be_success
      end

      it "skips the current branch input as text input when it is a file" do
        file_meta = { "blob_id" => blob.id, "filename" => "doc.txt" }
        context.current_input = file_meta
        context.set_variable("input", "fallback text")
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s,
                               "model" => "gpt-4.1",
                               "prompt" => "Summarize",
                             })

        response = double("response", content: "Summary") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask) do |_chat, message, **opts| # rubocop:disable RSpec/AnyInstance
          expect(message).to eq("fallback text")
          expect(opts[:with]).to be_present
          response
        end

        node.execute(context)
      end

      it "passes multiple file attachments when configured with several file_variables" do
        blob2 = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("second file"), filename: "doc2.txt", content_type: "text/plain",
        )
        file_vars = {
          "doc1" => { "blob_id" => blob.id, "filename" => "doc.txt" },
          "doc2" => { "blob_id" => blob2.id, "filename" => "doc2.txt" },
        }
        context.set_node_variables("input_1", file_vars)
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s, "model" => "gpt-4.1",
                               "prompt" => "Compare", "file_variables" => ["input_1.doc1", "input_1.doc2"],
                             })
        context.current_input = "Compare"

        response = double("response", content: "Comparison") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask) do |_chat, _msg, **opts| # rubocop:disable RSpec/AnyInstance
          expect(opts[:with]).to be_an(Array).and have_attributes(length: 2)
          response
        end

        expect(node.execute(context)).to be_success
      end

      it "auto-detects files from the current branch input array" do
        blob2 = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("second"), filename: "img2.png", content_type: "image/png",
        )
        context.current_input = [
          { "blob_id" => blob.id, "filename" => "doc.txt" },
          { "blob_id" => blob2.id, "filename" => "img2.png" },
        ]
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s, "model" => "gpt-4.1",
                               "prompt" => "Describe these files",
                             })

        response = double("response", content: "Description") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask) do |_chat, _msg, **opts| # rubocop:disable RSpec/AnyInstance
          expect(opts[:with]).to be_an(Array).and have_attributes(length: 2)
          response
        end

        expect(node.execute(context)).to be_success
      end

      it "falls through to prompt-only when file blob is not found" do
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s,
                               "model" => "gpt-4.1",
                               "prompt" => "Analyze",
                               "file_variables" => ["input_1.doc"],
                             })
        context.set_node_variables("input_1", { "doc" => { "blob_id" => -999, "filename" => "gone.txt" } })
        context.set_variable("input", "Analyze this")

        response = double("response", content: "Done") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask) do |_chat, _msg, **opts| # rubocop:disable RSpec/AnyInstance
          expect(opts[:with]).to be_nil
          response
        end

        result = node.execute(context)
        expect(result).to be_success
      end

      it "falls back to input variable when the current branch input is a file" do
        file_meta = { "blob_id" => blob.id, "filename" => "doc.txt" }
        context.current_input = file_meta
        context.set_variable("input", "text from input variable")
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s,
                               "model" => "gpt-4.1",
                               "prompt" => "Process",
                             })

        response = double("response", content: "Processed") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask) do |_chat, msg, **_opts| # rubocop:disable RSpec/AnyInstance
          expect(msg).to eq("text from input variable")
          response
        end

        result = node.execute(context)
        expect(result).to be_success
      end

      it "falls back to prompt when the current branch input is a file and input is nil" do
        file_meta = { "blob_id" => blob.id, "filename" => "doc.txt" }
        context.current_input = file_meta
        context.set_variable("_current_node_data", {
                               "connector_id" => connector.id.to_s,
                               "model" => "gpt-4.1",
                               "prompt" => "Process",
                             })

        response = double("response", content: "Processed") # rubocop:disable RSpec/VerifiedDoubles
        allow_any_instance_of(Chat).to receive(:ask).and_return(response) # rubocop:disable RSpec/AnyInstance

        result = node.execute(context)
        expect(result).to be_success
      end
    end
  end
end
