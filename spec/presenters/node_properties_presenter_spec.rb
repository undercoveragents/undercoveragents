# frozen_string_literal: true

require "rails_helper"

RSpec.describe NodePropertiesPresenter do
  let(:mission) { create(:mission, flow_data:) }

  let(:flow_data) do
    {
      "nodes" => [
        { "id" => "n1", "type" => "llm",
          "data" => { "label" => "My LLM", "prompt" => "Hello", "connector_id" => "42", "temperature" => 0.5 }, },
        { "id" => "n2", "type" => "condition", "data" => { "label" => "Check", "expression" => "x > 1" } },
        { "id" => "n3", "type" => "set_variable",
          "data" => { "label" => "Set Vars", "assignments" => { "foo" => "bar", "baz" => "qux" } }, },
      ],
      "edges" => [
        { "source" => "n1", "target" => "n2" },
        { "source" => "n2", "target" => "n3" },
      ],
    }
  end

  describe "#found?" do
    it "returns true when the node exists" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter).to be_found
    end

    it "returns false when the node does not exist" do
      presenter = described_class.new(mission:, node_id: "missing")
      expect(presenter).not_to be_found
    end

    it "returns false when mission flow data is nil" do
      mission_with_nil_flow = create(:mission)
      allow(mission_with_nil_flow).to receive(:flow_data).and_return(nil)

      presenter = described_class.new(mission: mission_with_nil_flow, node_id: "missing")

      expect(presenter).not_to be_found
      expect(presenter.upstream_file_variables).to eq([])
    end
  end

  describe "#node_label" do
    it "returns the label from node data" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.node_label).to eq("My LLM")
    end
  end

  describe "icon and color sanitization" do
    it "keeps valid Font Awesome tokens and strips unrelated classes" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm",
                      "data" => { "icon" => "custom fa-solid fa-robot extra", "color" => "#123abc" }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.node_icon).to eq("fa-solid fa-robot")
      expect(presenter.node_color).to eq("#123abc")
    end

    it "falls back to safe defaults for invalid icon markup and colors" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm",
                      "data" => {
                        "icon" => 'fa-solid"><script>alert(1)</script>',
                        "color" => "javascript:alert(1)",
                      }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.node_icon).to eq("fa-solid fa-circle")
      expect(presenter.node_color).to eq("#6366f1")
    end

    it "falls back when the icon contains no font awesome tokens" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm", "data" => { "icon" => "plain icon text" } }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.node_icon).to eq("fa-solid fa-circle")
    end
  end

  describe "#variable_name" do
    it "derives a normalized variable name from the node label" do
      presenter = described_class.new(mission:, node_id: "n1")

      expect(presenter.variable_name).to eq("my_llm")
    end

    it "returns a suffixed prefix when another node already uses the same label" do
      duplicated_flow = flow_data.deep_dup
      duplicated_flow["nodes"] << {
        "id" => "n4",
        "type" => "llm",
        "data" => { "label" => "My LLM", "prompt" => "Second" },
      }
      duplicated_mission = create(:mission, flow_data: duplicated_flow)

      presenter = described_class.new(mission: duplicated_mission, node_id: "n4")

      expect(presenter.variable_name).to eq("my_llm_2")
    end
  end

  describe "#node_type" do
    it "returns the node type" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.node_type).to eq("llm")
    end
  end

  describe "#temperature" do
    it "returns the configured temperature" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.temperature).to eq(0.5)
    end

    it "defaults to 0.7 when not set" do
      presenter = described_class.new(mission:, node_id: "n2")
      expect(presenter.temperature).to eq(0.7)
    end
  end

  describe "#data" do
    it "returns node data by key" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.data("prompt")).to eq("Hello")
    end

    it "returns the default when key is missing" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.data("nonexistent", "fallback")).to eq("fallback")
    end
  end

  describe "#assignments" do
    it "returns assignments hash for set_variable nodes" do
      presenter = described_class.new(mission:, node_id: "n3")
      expect(presenter.assignments).to eq({ "foo" => "bar", "baz" => "qux" })
    end

    it "returns empty hash when no assignments" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.assignments).to eq({})
    end
  end

  describe "#config_fields?" do
    it "returns true for known node types" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.config_fields?).to be(true)
    end

    it "returns false for a missing node" do
      presenter = described_class.new(mission:, node_id: "missing")
      expect(presenter.config_fields?).to be(false)
    end
  end

  describe "#valid?" do
    it "returns false when required fields are missing" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm", "data" => { "llm_config_source" => "node" } }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter).not_to be_valid
    end

    it "returns a validation message listing missing fields" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm", "data" => { "llm_config_source" => "node" } }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.validation_message).to include("is required")
    end
  end

  describe "#upstream_variables" do
    it "includes variables from upstream nodes" do
      presenter = described_class.new(mission:, node_id: "n3")
      names = presenter.upstream_variables.pluck(:name)
      expect(names).to include("my_llm.response")
    end
  end

  describe "#selectable_upstream_variables" do
    it "excludes variables starting with underscore" do
      presenter = described_class.new(mission:, node_id: "n3")
      names = presenter.selectable_upstream_variables.pluck(:name)
      expect(names).not_to include("_current_node_data")
    end
  end

  describe "#headers_value" do
    it "returns JSON string for hash headers" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => { "headers" => { "X-Key" => "val" } }, }], "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.headers_value).to include("X-Key")
    end

    it "returns string representation for non-hash headers" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => { "headers" => "X-Custom: value" }, }], "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.headers_value).to eq("X-Custom: value")
    end
  end

  describe "HTTP request helpers" do
    it "normalizes structured HTTP hashes" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => {
                        "params" => { "q" => "cats" },
                        "form_urlencoded_body" => { "name" => "Taylor" },
                        "multipart_form_data" => { "document" => "{{doc}}" },
                      }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.http_params).to eq({ "q" => "cats" })
      expect(presenter.http_form_urlencoded_body).to eq({ "name" => "Taylor" })
      expect(presenter.http_multipart_form_data).to eq({ "document" => "{{doc}}" })
    end

    it "parses string HTTP hashes and falls back for invalid values" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => {
                        "headers" => '{"Accept":"application/json"}',
                        "params" => 12,
                        "form_urlencoded_body" => "{invalid",
                      }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.http_headers).to eq({ "Accept" => "application/json" })
      expect(presenter.http_params).to eq({})
      expect(presenter.http_form_urlencoded_body).to eq({})
    end

    it "returns explicit HTTP body modes when configured" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => { "body_mode" => "multipart", "body" => '{"ok":true}' }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.http_body_mode).to eq("multipart")
    end

    it "normalizes known and unknown HTTP auth types" do
      valid_flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => { "auth_type" => "basic" }, }],
        "edges" => [],
      }
      invalid_flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => { "auth_type" => "mystery" }, }],
        "edges" => [],
      }

      valid_presenter = described_class.new(mission: create(:mission, flow_data: valid_flow), node_id: "n1")
      invalid_presenter = described_class.new(mission: create(:mission, flow_data: invalid_flow), node_id: "n1")

      expect(valid_presenter.http_auth_type).to eq("basic")
      expect(invalid_presenter.http_auth_type).to eq("none")
    end

    it "defaults missing legacy body modes to none" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => { "body" => '{"ok":true}', "headers" => { "Content-Type" => "application/json" } }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.http_body_mode).to eq("none")
    end

    it "returns none when no body content exists" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request", "data" => { "body_mode" => "custom" } }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.http_body_mode).to eq("none")
    end

    it "defaults verify_ssl to true and retry_enabled to false" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request", "data" => {} }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.http_verify_ssl?).to be(true)
      expect(presenter.http_retry_enabled?).to be(false)
    end

    it "reads explicit verify_ssl and retry_enabled settings" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "http_request",
                      "data" => { "verify_ssl" => false, "retry_enabled" => true }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.http_verify_ssl?).to be(false)
      expect(presenter.http_retry_enabled?).to be(true)
    end

    it "builds file variable options for the HTTP file picker" do
      flow = {
        "nodes" => [
          { "id" => "wf1", "type" => "write_file",
            "data" => { "label" => "Write", "filename" => "out.txt", "content" => "hello" }, },
          { "id" => "http1", "type" => "http_request",
            "data" => { "label" => "Upload", "method" => "POST", "url" => "https://api.example.com/upload" }, },
        ],
        "edges" => [{ "source" => "wf1", "target" => "http1" }],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "http1")

      expect(presenter.http_file_reference_options).to contain_exactly(
        hash_including(
          label: "write.file",
          value: "{{write.file}}",
          description: include("File metadata"),
        ),
      )
    end
  end

  describe "#cases" do
    it "returns cases hash when present" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "switch",
                      "data" => { "label" => "Switch", "expression" => "x", "cases" => { "a" => "1" } }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.cases).to eq({ "a" => "1" })
    end
  end

  describe "#selected_variables" do
    it "returns selected variables when present" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "output",
                      "data" => { "label" => "Out", "selected_variables" => ["x", "y"] }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.selected_variables).to eq(["x", "y"])
    end

    it "returns empty array when not set" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.selected_variables).to eq([])
    end
  end

  describe "#available_models" do
    it "returns models for a valid LLM connector" do
      connector = create(:connector, :llm_provider, name: "TestLLM")
      create(:model, provider: connector.provider, model_id: "gpt-4", name: "GPT-4")
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm",
                      "data" => { "connector_id" => connector.id.to_s }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.available_models.map(&:model_id)).to include("gpt-4")
    end

    it "returns empty array when connector_id is blank" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm", "data" => {} }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.available_models).to eq([])
    end

    it "returns empty array for non-LLM connectors" do
      connector = create(:connector, :sql_database)
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm",
                      "data" => { "connector_id" => connector.id.to_s }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.available_models).to eq([])
    end

    it "returns empty array when the connector record cannot be found" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm",
                      "data" => { "connector_id" => "999999" }, }],
        "edges" => [],
      }
      presenter = described_class.new(mission: create(:mission, flow_data: flow), node_id: "n1")

      expect(presenter.available_models).to eq([])
    end
  end

  describe "#available_tools" do
    it "returns enabled tools scoped to the mission operation" do
      enabled_tool = create(:tool, :mission_tool, :enabled, operation: mission.operation)
      create(:tool, :mission_tool, :disabled, operation: mission.operation)
      create(:tool, :mission_tool, :enabled, operation: create(:operation))

      presenter = described_class.new(mission:, node_id: "n1")

      expect(presenter.available_tools).to contain_exactly(enabled_tool)
    end
  end

  describe "#selected_tool_ids" do
    it "normalizes configured tool ids to integers" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "llm", "data" => { "tool_ids" => ["4", "oops", 7] } }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")

      expect(presenter.selected_tool_ids).to eq([4, 7])
    end
  end

  describe "#available_image_models" do
    let(:image_connector) { create(:connector, :llm_provider, name: "Image LLM") }
    let(:image_model) do
      create(
        :model,
        provider: image_connector.provider,
        model_id: "gpt-image-1",
        name: "GPT Image",
        modalities: { "output" => ["image"] },
      )
    end
    let(:text_model) do
      create(
        :model,
        provider: image_connector.provider,
        model_id: "gpt-4.1",
        name: "GPT Text",
        modalities: { "output" => ["text"] },
      )
    end
    let(:image_flow_data) do
      {
        "nodes" => [
          { "id" => "n1", "type" => "generate_image",
            "data" => { "connector_id" => image_connector.id.to_s }, },
        ],
        "edges" => [],
      }
    end

    it "returns only image-capable models for the connector provider" do
      image_model
      text_model
      m = create(:mission, flow_data: image_flow_data)
      presenter = described_class.new(mission: m, node_id: "n1")

      expect(presenter.available_image_models.map(&:model_id)).to eq(["gpt-image-1"])
    end
  end

  describe "#valid? for a valid node" do
    it "returns true when all required fields are present" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "set_variable",
                      "data" => { "label" => "S", "assignments" => { "x" => "1" } }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter).to be_valid
      expect(presenter.validation_message).to eq("")
    end
  end

  describe "#node_icon and #node_color fallbacks" do
    it "falls back to defaults for a missing node" do
      presenter = described_class.new(mission:, node_id: "missing")
      expect(presenter.node_icon).to eq("fa-solid fa-circle")
      expect(presenter.node_color).to eq("#6366f1")
    end
  end

  describe "#output_variables with extractions" do
    it "expands extraction-based dynamic outputs" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "json_extract",
                      "data" => { "label" => "Extract", "source" => "data",
                                  "extractions" => { "name" => "$.name", "age" => "$.age" }, }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      names = presenter.output_variables.pluck(:name)
      expect(names).to include("extract.name")
      expect(names).to include("extract.age")
    end
  end

  describe "#output_variables with assignments" do
    it "expands assignment-based dynamic outputs" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "set_variable",
                      "data" => { "label" => "Set Vars",
                                  "assignments" => { "score" => "42", "status" => "ok" }, }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      names = presenter.output_variables.pluck(:name)
      expect(names).to include("set_vars.score")
      expect(names).to include("set_vars.status")
    end
  end

  describe "#fields" do
    it "returns fields array for input nodes" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "input",
                      "data" => { "fields" => [{ "variable_name" => "name", "label" => "Name" }] }, }], "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.fields).to eq([{ "variable_name" => "name", "label" => "Name" }])
    end
  end

  describe "#node_type_label fallback chain" do
    it "uses metadata label for known node types" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.node_type_label).to eq("Generate Text")
    end

    it "falls back to node_type titleized when metadata has no label" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "unknown_custom_type", "data" => { "label" => "Foo" } }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter.node_type_label).to eq("Unknown Custom Type")
    end

    it "falls back to Unknown when node is not found" do
      presenter = described_class.new(mission:, node_id: "missing")
      expect(presenter.node_type_label).to eq("Unknown")
    end
  end

  describe "#node_icon and #node_color metadata fallbacks" do
    it "uses metadata icon when node data has no icon" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.node_icon).to eq("fa-solid fa-brain")
    end

    it "uses metadata color when node data has no color" do
      presenter = described_class.new(mission:, node_id: "n1")
      expect(presenter.node_color).to eq("#6366f1")
    end

    it "prefers explicit node icon and color overrides" do
      flow = {
        "nodes" => [{
          "id" => "n1",
          "type" => "llm",
          "data" => {
            "label" => "Styled",
            "prompt" => "Hello",
            "icon" => "fa-solid fa-star",
            "color" => "#112233",
          },
        }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")

      expect(presenter.node_icon).to eq("fa-solid fa-star")
      expect(presenter.node_color).to eq("#112233")
    end
  end

  describe "#find_node with nil flow_data" do
    it "handles nil flow_data gracefully" do
      m = build_stubbed(:mission, flow_data: nil)
      presenter = described_class.new(mission: m, node_id: "n1")
      expect(presenter).not_to be_found
    end
  end

  describe "#output_variables with blank variable_name in fields" do
    it "skips fields with blank variable_name" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "input",
                      "data" => { "label" => "Start",
                                  "fields" => [
                                    { "variable_name" => "name", "label" => "Name" },
                                    { "variable_name" => "", "label" => "Empty" },
                                    { "variable_name" => nil, "label" => "Nil" },
                                  ], }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      names = presenter.output_variables.pluck(:name)
      expect(names).to include("start.name")
      expect(names).not_to include("start.")
    end
  end

  describe "#output_variables for code node with output_variables" do
    it "includes configured output variables alongside result" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "code",
                      "data" => { "label" => "Transform", "code" => "1 + 1",
                                  "output_variables" => [
                                    { "name" => "count", "description" => "Item count" },
                                    { "name" => "total", "description" => "Running total" },
                                  ], }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      names = presenter.output_variables.pluck(:name)
      expect(names).to include("transform.result")
      expect(names).to include("transform.count")
      expect(names).to include("transform.total")
    end

    it "uses default description when description is blank" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "code",
                      "data" => { "label" => "Transform", "code" => "1",
                                  "output_variables" => [
                                    { "name" => "val", "description" => "" },
                                  ], }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      var = presenter.output_variables.find { |v| v[:name] == "transform.val" }
      expect(var[:description]).to eq("Code output variable")
    end

    it "skips output variables with blank names" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "code",
                      "data" => { "label" => "Transform", "code" => "1",
                                  "output_variables" => [
                                    { "name" => "", "description" => "Empty" },
                                    { "name" => "valid", "description" => "Valid" },
                                  ], }, }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")
      names = presenter.output_variables.pluck(:name)
      expect(names).to include("transform.valid")
      expect(names).not_to include("transform.")
    end
  end

  describe "#output_variables for static schemas" do
    it "returns schema-defined output variables for known node types" do
      presenter = described_class.new(mission:, node_id: "n1")

      expect(presenter.output_variables).to include(
        hash_including(name: "my_llm.response", type: "out"),
      )
    end

    it "returns no output variables for unknown node types" do
      flow = {
        "nodes" => [{ "id" => "n1", "type" => "totally_unknown_type", "data" => { "label" => "Mystery" } }],
        "edges" => [],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "n1")

      expect(presenter.output_variables).to eq([])
    end
  end

  describe "#upstream_file_variables" do
    it "includes variables from generate_image upstream nodes" do
      flow = {
        "nodes" => [
          { "id" => "img1", "type" => "generate_image",
            "data" => { "label" => "Gen Img", "connector_id" => "1", "model" => "dall-e-3" }, },
          { "id" => "llm1", "type" => "llm",
            "data" => { "label" => "Gen Text", "connector_id" => "1", "model" => "gpt-4.1" }, },
        ],
        "edges" => [{ "source" => "img1", "target" => "llm1" }],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "llm1")
      names = presenter.upstream_file_variables.pluck(:name)

      expect(names).to include("gen_img.image")
    end

    it "includes file fields from input nodes" do
      flow = {
        "nodes" => [
          { "id" => "inp1", "type" => "input",
            "data" => { "label" => "Input",
                        "fields" => [{ "variable_name" => "doc", "field_type" => "file", "required" => true }], }, },
          { "id" => "llm1", "type" => "llm",
            "data" => { "label" => "Gen Text", "connector_id" => "1", "model" => "gpt-4.1" }, },
        ],
        "edges" => [{ "source" => "inp1", "target" => "llm1" }],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "llm1")
      names = presenter.upstream_file_variables.pluck(:name)

      expect(names).to include("input.doc")
    end

    it "excludes non-file fields from input nodes" do
      flow = {
        "nodes" => [
          { "id" => "inp1", "type" => "input",
            "data" => { "label" => "Input",
                        "fields" => [{ "variable_name" => "query", "field_type" => "string" }], }, },
          { "id" => "llm1", "type" => "llm",
            "data" => { "label" => "Gen Text", "connector_id" => "1", "model" => "gpt-4.1" }, },
        ],
        "edges" => [{ "source" => "inp1", "target" => "llm1" }],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "llm1")

      expect(presenter.upstream_file_variables).to be_empty
    end

    it "includes write_file upstream variables" do
      flow = {
        "nodes" => [
          { "id" => "wf1", "type" => "write_file",
            "data" => { "label" => "Write", "filename" => "out.txt", "content" => "hello" }, },
          { "id" => "llm1", "type" => "llm",
            "data" => { "label" => "Gen Text", "connector_id" => "1", "model" => "gpt-4.1" }, },
        ],
        "edges" => [{ "source" => "wf1", "target" => "llm1" }],
      }
      m = create(:mission, flow_data: flow)
      presenter = described_class.new(mission: m, node_id: "llm1")
      names = presenter.upstream_file_variables.pluck(:name)

      expect(names).to include("write.file")
    end

    it "returns an empty list when the mission has no flow data" do
      presenter = described_class.new(mission: build_stubbed(:mission, flow_data: nil), node_id: "n1")

      expect(presenter.upstream_file_variables).to eq([])
    end
  end
end
