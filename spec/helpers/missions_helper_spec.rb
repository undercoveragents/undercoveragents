# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionsHelper do
  describe "#extract_workflow_variables" do
    context "with an input node with fields" do
      it "adds a variable for each input field" do
        flow = {
          "nodes" => [
            { "id" => "t1", "type" => "input",
              "data" => { "label" => "Start", "fields" => [{ "variable_name" => "query" }] }, },
          ],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("query")
      end

      it "includes field_type metadata from input fields" do
        flow = {
          "nodes" => [
            { "id" => "t1", "type" => "input",
              "data" => { "label" => "Start",
                          "fields" => [{ "variable_name" => "count", "field_type" => "number",
                                         "label" => "Count", }], }, },
          ],
        }
        vars = helper.extract_workflow_variables(flow)
        count_var = vars.find { |v| v[:key] == "count" }
        expect(count_var[:field_type]).to eq("number")
        expect(count_var[:category]).to eq("trigger")
      end

      it "skips fields with blank variable_name" do
        flow = {
          "nodes" => [
            { "id" => "t1", "type" => "input",
              "data" => { "label" => "Start", "fields" => [{ "variable_name" => "" }, { "variable_name" => "q" }] }, },
          ],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to eq(["q"])
      end
    end

    context "with an llm node that has a templated prompt" do
      it "extracts template variables from the prompt" do
        flow = {
          "nodes" => [{
            "id" => "n1", "type" => "llm",
            "data" => { "label" => "My LLM", "prompt" => "Hello {{user_name}}, topic: {{topic}}" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        keys = vars.pluck(:key)
        expect(keys).to include("user_name", "topic")
        expect(vars.find { |v| v[:key] == "user_name" }[:category]).to eq("template")
      end
    end

    context "with an agent node" do
      it "extracts template variables from the agent prompt" do
        flow = {
          "nodes" => [{
            "id" => "n1", "type" => "agent",
            "data" => { "label" => "My Agent", "prompt" => "Summarise {{document}}" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("document")
      end
    end

    context "with an output node with selected variables" do
      it "does not add selected variables as inputs" do
        flow = {
          "nodes" => [{
            "id" => "o1", "type" => "output",
            "data" => { "label" => "Reply", "selected_variables" => ["result"] },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).not_to include("result")
      end
    end

    context "with a condition node" do
      it "extracts expression variables" do
        flow = {
          "nodes" => [{
            "id" => "c1", "type" => "condition",
            "data" => { "label" => "Check", "expression" => "score > threshold" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        keys = vars.pluck(:key)
        expect(keys).to include("score", "threshold")
        expect(vars.find { |v| v[:key] == "score" }[:category]).to eq("expression")
      end

      it "skips reserved expression words" do
        flow = {
          "nodes" => [{
            "id" => "c1", "type" => "condition",
            "data" => { "expression" => "true and false or not nil" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars).to be_empty
      end
    end

    context "with a switch node" do
      it "extracts template variables from the expression" do
        flow = {
          "nodes" => [{
            "id" => "sw1", "type" => "switch",
            "data" => { "label" => "Route", "expression" => "{{category}}" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("category")
      end
    end

    context "with an iterator node" do
      it "adds a variable for a simple identifier collection" do
        flow = {
          "nodes" => [{
            "id" => "i1", "type" => "iterator",
            "data" => { "label" => "Iterate", "collection" => "items" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("items")
        expect(vars.find { |v| v[:key] == "items" }[:category]).to eq("expression")
      end

      it "does not add a variable for a literal JSON array collection" do
        flow = {
          "nodes" => [{
            "id" => "i1", "type" => "iterator",
            "data" => { "collection" => '["a","b"]' },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).not_to include('["a","b"]')
      end
    end

    context "with a loop node" do
      it "extracts expression variables from the condition" do
        flow = {
          "nodes" => [{
            "id" => "lp1", "type" => "loop",
            "data" => { "condition" => "counter < limit" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("counter", "limit")
      end
    end

    it "deduplicates variables across multiple nodes" do
      flow = {
        "nodes" => [
          { "id" => "n1", "type" => "llm", "data" => { "prompt" => "Hello {{name}}" } },
          { "id" => "n2", "type" => "llm", "data" => { "prompt" => "Bye {{name}}" } },
        ],
      }
      vars = helper.extract_workflow_variables(flow)
      expect(vars.count { |v| v[:key] == "name" }).to eq(1)
    end

    it "skips internal variable names in template vars" do
      flow = {
        "nodes" => [{
          "id" => "n1", "type" => "llm",
          "data" => { "prompt" => "{{_current_node_data}} and {{_current_node_id}}" },
        }],
      }
      vars = helper.extract_workflow_variables(flow)
      expect(vars.pluck(:key)).not_to include("_current_node_data", "_current_node_id")
    end

    it "returns an empty array when flow_data is nil" do
      expect(helper.extract_workflow_variables(nil)).to eq([])
    end

    it "returns an empty array when nodes is absent" do
      expect(helper.extract_workflow_variables({})).to eq([])
    end

    context "with a text_template node" do
      it "extracts template variables from the template" do
        flow = {
          "nodes" => [{
            "id" => "tt1", "type" => "text_template",
            "data" => { "label" => "Render", "template" => "Hello {{user_name}}, your score is {{score}}" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("user_name", "score")
      end
    end

    context "with an http_request node" do
      it "extracts template variables from url and body" do
        flow = {
          "nodes" => [{
            "id" => "hr1", "type" => "http_request",
            "data" => {
              "label" => "API Call",
              "url" => "https://api.example.com/{{endpoint}}",
              "body" => '{"q": "{{query}}"}',
            },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("endpoint", "query")
      end

      it "extracts template variables from string headers" do
        flow = {
          "nodes" => [{
            "id" => "hr1", "type" => "http_request",
            "data" => { "headers" => '{"Authorization": "Bearer {{token}}"}' },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("token")
      end

      it "extracts template variables from query params and auth fields" do
        flow = {
          "nodes" => [{
            "id" => "hr1", "type" => "http_request",
            "data" => {
              "params" => { "q" => "{{query}}" },
              "auth_bearer_token" => "{{token}}",
            },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("query", "token")
      end

      it "extracts template variables from form and multipart bodies" do
        flow = {
          "nodes" => [{
            "id" => "hr1", "type" => "http_request",
            "data" => {
              "form_urlencoded_body" => { "status" => "{{state}}" },
              "multipart_form_data" => { "document" => "{{write_file_1.file}}" },
            },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("state", "write_file_1.file")
      end
    end

    context "with a filter node" do
      it "extracts collection variable and expression variables" do
        flow = {
          "nodes" => [{
            "id" => "f1", "type" => "filter",
            "data" => { "label" => "Filter", "collection" => "items", "expression" => "item > threshold" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        keys = vars.pluck(:key)
        expect(keys).to include("items", "item", "threshold")
      end
    end

    context "with a set_variable node" do
      it "extracts template variables from assignment expressions" do
        flow = {
          "nodes" => [{
            "id" => "sv1", "type" => "set_variable",
            "data" => { "label" => "Set Vars", "assignments" => { "greeting" => "Hello {{user_name}}" } },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("user_name")
      end

      it "marks assignment keys as produced so downstream nodes do not re-extract them" do
        flow = {
          "nodes" => [
            { "id" => "sv1", "type" => "set_variable",
              "data" => { "label" => "Store URL", "assignments" => { "operation_location" => "{{headers}}" } }, },
            { "id" => "hr1", "type" => "http_request",
              "data" => { "label" => "Poll", "url" => "{{operation_location}}" }, },
          ],
        }
        vars = helper.extract_workflow_variables(flow)
        keys = vars.pluck(:key)
        expect(keys).to include("headers")
        expect(keys).not_to include("operation_location")
      end

      it "handles empty assignments gracefully" do
        flow = { "nodes" => [{ "id" => "sv1", "type" => "set_variable", "data" => {} }] }
        expect { helper.extract_workflow_variables(flow) }.not_to raise_error
      end
    end

    context "with a json_extract node" do
      it "extracts template variables from the source" do
        flow = {
          "nodes" => [{
            "id" => "je1", "type" => "json_extract",
            "data" => { "label" => "Parse", "source" => "{{json_response}}" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("json_response")
      end
    end

    context "with a delay node" do
      it "extracts template variables from a templated duration" do
        flow = {
          "nodes" => [{
            "id" => "d1", "type" => "delay",
            "data" => { "label" => "Wait", "duration" => "{{wait_time}}" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("wait_time")
      end

      it "skips extraction when duration is a plain number" do
        flow = { "nodes" => [{ "id" => "d1", "type" => "delay", "data" => { "duration" => "5" } }] }
        vars = helper.extract_workflow_variables(flow)
        expect(vars).to be_empty
      end
    end

    context "with array-manipulation nodes" do
      ["aggregate", "sort", "unique", "limit"].each do |node_type|
        it "extracts a collection variable from #{node_type} node" do
          flow = {
            "nodes" => [{
              "id" => "n1", "type" => node_type,
              "data" => { "label" => node_type.titleize, "collection" => "results" },
            }],
          }
          vars = helper.extract_workflow_variables(flow)
          expect(vars.pluck(:key)).to include("results")
        end

        it "skips non-identifier collection in #{node_type} node" do
          flow = {
            "nodes" => [{ "id" => "n1", "type" => node_type, "data" => { "collection" => "[1,2,3]" } }],
          }
          vars = helper.extract_workflow_variables(flow)
          expect(vars).to be_empty
        end
      end
    end

    context "with collection nodes missing the collection key" do
      it "handles aggregate with nil collection gracefully" do
        flow = { "nodes" => [{ "id" => "n1", "type" => "aggregate", "data" => {} }] }
        vars = helper.extract_workflow_variables(flow)
        expect(vars).to be_empty
      end
    end

    context "with http_request node with hash headers" do
      it "extracts template variables from hash header values" do
        flow = {
          "nodes" => [{
            "id" => "hr1", "type" => "http_request",
            "data" => { "headers" => { "Authorization" => "Bearer {{token}}", "Content-Type" => "application/json" } },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars.pluck(:key)).to include("token")
      end

      it "does not extract from plain-value hash headers" do
        flow = {
          "nodes" => [{
            "id" => "hr1", "type" => "http_request",
            "data" => { "headers" => { "Content-Type" => "application/json" } },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        expect(vars).to be_empty
      end
    end

    context "with a condition node using expression functions and string literals" do
      it "skips expression function names and string literal contents" do
        flow = {
          "nodes" => [{
            "id" => "c1", "type" => "condition",
            "data" => {
              "label" => "Check",
              "expression" => "CONTAINS({{body}}, 'succeeded') OR LEN({{text}}) > 0",
            },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        keys = vars.pluck(:key)
        expect(keys).to include("body", "text")
        expect(keys).not_to include("CONTAINS", "LEN", "succeeded")
      end

      it "categorizes {{var}} in expressions as template variables" do
        flow = {
          "nodes" => [{
            "id" => "c1", "type" => "condition",
            "data" => { "label" => "Check", "expression" => "{{score}} > 0.5" },
          }],
        }
        vars = helper.extract_workflow_variables(flow)
        score_var = vars.find { |v| v[:key] == "score" }
        expect(score_var[:category]).to eq("template")
      end
    end
  end

  describe "#format_debug_output" do
    it "returns a string as-is" do
      expect(helper.format_debug_output("hello world")).to eq("hello world")
    end

    it "returns an empty string for nil" do
      expect(helper.format_debug_output(nil)).to eq("")
    end

    it "pretty-prints non-string non-nil values as JSON" do
      expect(helper.format_debug_output({ "key" => "value" })).to include('"key"')
    end

    it "falls back to to_s for values that cannot be serialized to JSON" do
      weird = Object.new
      def weird.to_json(*) = raise(JSON::GeneratorError, "cannot serialize")
      def weird.to_s = "custom_object"
      expect(helper.format_debug_output(weird)).to eq("custom_object")
    end
  end

  describe "#status_badge_html" do
    it "returns an HTML span with success icon" do
      html = helper.status_badge_html("success")
      expect(html).to include("fa-circle-check")
      expect(html).to include("Success")
    end

    it "falls back gracefully for unknown status keys" do
      html = helper.status_badge_html("unknown_status")
      expect(html).to include("unknown_status")
    end
  end

  describe "#run_status_config" do
    it "returns config for known statuses" do
      config = helper.run_status_config("running")
      expect(config[:icon]).to include("fa-spinner")
      expect(config[:color]).to be_present
    end

    it "returns the 'none' config for unknown statuses" do
      config = helper.run_status_config("not_a_real_status")
      expect(config).to eq(MissionsHelper::RUN_STATUS_CONFIG["none"])
    end
  end

  describe "#node_variable_schemas_json" do
    it "skips type keys whose plugin class cannot be resolved" do
      allow(MissionNodePlugin).to receive(:type_keys).and_return(["ghost_type"])
      allow(MissionNodePlugin).to receive(:resolve).with("ghost_type").and_return(nil)

      result = JSON.parse(helper.node_variable_schemas_json)

      expect(result).to be_empty
    end

    it "includes variable schemas for resolvable node types" do
      result = JSON.parse(helper.node_variable_schemas_json)

      expect(result).to be_a(Hash)
      expect(result).to include("llm")
      expect(result["llm"]).to have_key("inputs")
      expect(result["llm"]).to have_key("outputs")
    end
  end

  describe "#extract_workflow_variables edge cases" do
    it "ignores nodes with an unrecognised type (case :else branch)" do
      flow = { "nodes" => [{ "id" => "n1", "type" => "unknown_custom_node", "data" => {} }] }
      expect { helper.extract_workflow_variables(flow) }.not_to raise_error
    end

    it "handles iterator node without collection (nil collection &.strip)" do
      flow = { "nodes" => [{ "id" => "it1", "type" => "iterator", "data" => {} }] }
      expect { helper.extract_workflow_variables(flow) }.not_to raise_error
    end

    it "returns no variables when llm node prompt is blank" do
      flow = { "nodes" => [{ "id" => "n1", "type" => "llm", "data" => { "prompt" => nil } }] }
      vars = helper.extract_workflow_variables(flow)
      expect(vars).to be_empty
    end

    it "returns no variables when condition expression is blank" do
      flow = { "nodes" => [{ "id" => "c1", "type" => "condition", "data" => { "expression" => nil } }] }
      vars = helper.extract_workflow_variables(flow)
      expect(vars).to be_empty
    end
  end

  describe "#extract_workflow_variables with global variables" do
    it "extracts global variables from flow_data" do
      flow = {
        "nodes" => [],
        "global_variables" => [
          { "key" => "api_key", "value" => "secret", "type" => "string" },
          { "key" => "threshold", "value" => "0.8", "type" => "number" },
        ],
      }
      vars = helper.extract_workflow_variables(flow)
      global_vars = vars.select { |v| v[:category] == "global" }
      expect(global_vars.size).to eq(2)
      expect(global_vars.pluck(:key)).to contain_exactly("api_key", "threshold")
      expect(global_vars.first[:source]).to eq("Global")
      expect(global_vars.first[:default_value]).to eq("secret")
    end

    it "omits default_value when global variable value is blank" do
      flow = {
        "nodes" => [],
        "global_variables" => [{ "key" => "empty", "value" => "", "type" => "string" }],
      }
      vars = helper.extract_workflow_variables(flow)
      expect(vars.first).not_to have_key(:default_value)
    end

    it "returns empty when no global variables" do
      flow = { "nodes" => [], "global_variables" => [] }
      vars = helper.extract_workflow_variables(flow)
      global_vars = vars.select { |v| v[:category] == "global" }
      expect(global_vars).to be_empty
    end

    it "skips global variables with blank keys" do
      flow = {
        "nodes" => [],
        "global_variables" => [
          { "key" => "", "value" => "ignored", "type" => "string" },
          { "key" => "valid", "value" => "kept", "type" => "string" },
        ],
      }
      vars = helper.extract_workflow_variables(flow)
      global_vars = vars.select { |v| v[:category] == "global" }
      expect(global_vars.size).to eq(1)
      expect(global_vars.first[:key]).to eq("valid")
    end
  end

  describe "#file_output?" do
    it "returns true for a hash with blob_id and filename" do
      expect(helper.file_output?({ "blob_id" => 1, "filename" => "test.txt" })).to be true
    end

    it "returns false for a regular hash" do
      expect(helper.file_output?({ "key" => "value" })).to be false
    end

    it "returns false for a string" do
      expect(helper.file_output?("hello")).to be false
    end

    it "returns false for nil" do
      expect(helper.file_output?(nil)).to be false
    end

    it "returns true for an array containing file hashes" do
      files = [
        { "blob_id" => 1, "filename" => "a.txt" },
        { "blob_id" => 2, "filename" => "b.txt" },
      ]
      expect(helper.file_output?(files)).to be true
    end

    it "returns false for an array without file hashes" do
      expect(helper.file_output?([{ "key" => "value" }])).to be false
    end
  end

  describe "#file_download_link" do
    it "returns filename when blob not found" do
      value = { "blob_id" => -1, "filename" => "missing.txt" }
      expect(helper.file_download_link(value)).to eq("missing.txt")
    end

    it "returns a download link when blob exists" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("content"), filename: "test.txt", content_type: "text/plain",
      )
      value = { "blob_id" => blob.id, "filename" => "test.txt" }
      result = helper.file_download_link(value)

      expect(result).to include("fa-download")
      expect(result).to include("test.txt")
      expect(result).to include("ms-debug-file-link")
      expect(result).not_to include("ms-debug-image-preview")
    end

    it "includes an image preview for image blobs" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("fake-image"), filename: "photo.png", content_type: "image/png",
      )
      value = { "blob_id" => blob.id, "filename" => "photo.png" }
      result = helper.file_download_link(value)

      expect(result).to include("ms-debug-file-link")
      expect(result).to include("ms-debug-image-preview")
      expect(result).to include("<img")
    end

    it "renders multiple download links for an array of files" do
      blob1 = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("content1"), filename: "file1.txt", content_type: "text/plain",
      )
      blob2 = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("content2"), filename: "file2.txt", content_type: "text/plain",
      )
      values = [
        { "blob_id" => blob1.id, "filename" => "file1.txt" },
        { "blob_id" => blob2.id, "filename" => "file2.txt" },
      ]
      result = helper.file_download_link(values)

      expect(result).to include("file1.txt")
      expect(result).to include("file2.txt")
    end

    it "skips non-file entries in an array" do
      blob1 = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("content1"), filename: "file1.txt", content_type: "text/plain",
      )
      values = [
        { "blob_id" => blob1.id, "filename" => "file1.txt" },
        { "not_a_file" => true },
      ]
      result = helper.file_download_link(values)

      expect(result).to include("file1.txt")
      expect(result).not_to include("not_a_file")
    end

    it "renders link without preview when content_type is nil" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("data"), filename: "unknown.bin", content_type: "application/octet-stream",
      )
      blob.update_column(:content_type, nil) # rubocop:disable Rails/SkipsModelValidations
      value = { "blob_id" => blob.id, "filename" => "unknown.bin" }
      result = helper.file_download_link(value)

      expect(result).to include("fa-download")
      expect(result).not_to include("ms-debug-image-preview")
    end
  end
end
