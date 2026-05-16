# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::HttpRequest do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns http_request" do
      expect(described_class.node_type).to eq("http_request")
    end
  end

  describe ".node_category" do
    it "is node" do
      expect(described_class.node_category).to eq(:node)
    end
  end

  describe ".required_field_keys" do
    it "requires url and method" do
      expect(described_class.required_field_keys).to eq(["url", "method"])
    end
  end

  describe ".variable_schema" do
    it "declares outputs" do
      schema = described_class.variable_schema
      expect(schema.outputs.map(&:name)).to include("status", "body", "headers")
    end
  end

  describe ".input_schema" do
    it "declares url and method config inputs" do
      expect(described_class.input_schema.pluck(:name)).to include("url", "method")
    end
  end

  describe ".extract_variables" do
    let(:variables) { [] }
    let(:seen) { Set.new }

    it "extracts template variables from url" do
      described_class.extract_variables(
        { "url" => "https://api.example.com/{{resource}}", "body" => "" },
        "HTTP", variables, seen,
      )
      expect(seen).to include("resource")
    end

    it "extracts template variables from body" do
      described_class.extract_variables(
        { "url" => "", "body" => "{{payload}}" },
        "HTTP", variables, seen,
      )
      expect(seen).to include("payload")
    end

    it "extracts template variables from string headers" do
      described_class.extract_variables(
        { "url" => "", "body" => "", "headers" => '{"Authorization": "Bearer {{token}}"}' },
        "HTTP", variables, seen,
      )
      expect(seen).to include("token")
    end

    it "extracts template variables from hash header values" do
      described_class.extract_variables(
        { "url" => "", "body" => "", "headers" => { "Authorization" => "Bearer {{api_key}}" } },
        "HTTP", variables, seen,
      )
      expect(seen).to include("api_key")
    end

    it "extracts template variables from params and authorization fields" do
      described_class.extract_variables(
        {
          "url" => "",
          "body" => "",
          "params" => { "q" => "{{query}}" },
          "auth_bearer_token" => "{{token}}",
          "auth_api_key_value" => "{{api_key}}",
        },
        "HTTP", variables, seen,
      )
      expect(seen).to include("query", "token", "api_key")
    end

    it "extracts template variables from encoded and multipart body fields" do
      described_class.extract_variables(
        {
          "url" => "",
          "body" => "",
          "form_urlencoded_body" => { "status" => "{{state}}" },
          "multipart_form_data" => { "document" => "{{input_1.document}}" },
          "binary_source" => "{{write_file_1.file}}",
        },
        "HTTP", variables, seen,
      )
      expect(seen).to include("state", "input_1.document", "write_file_1.file")
    end

    it "extracts template variables from array-based HTTP config values" do
      described_class.extract_variables(
        {
          "url" => "",
          "body" => "",
          "headers" => [{ "Authorization" => "Bearer {{token}}" }],
          "multipart_form_data" => ["{{write_file_1.file}}"],
        },
        "HTTP", variables, seen,
      )

      expect(seen).to include("token", "write_file_1.file")
    end

    it "handles nil headers without error" do
      expect do
        described_class.extract_variables({ "url" => "", "body" => "", "headers" => nil }, "HTTP", variables, seen)
      end.not_to raise_error
    end
  end

  describe ".designer_instructions" do
    it "includes http_request type reference" do
      expect(described_class.designer_instructions).to include("http_request")
    end
  end

  describe "#output_ports" do
    it "has success and error ports" do
      expect(node.output_ports).to eq([
                                        { key: "success", label: "Success (2xx)" },
                                        { key: "error", label: "Error" },
                                      ])
    end
  end

  describe "#execute" do
    it "fails with invalid HTTP method" do
      context.set_variable("_current_node_data", { "url" => "https://example.com", "method" => "INVALID" })
      result = node.execute(context)
      expect(result).to be_failure
      expect(result.output).to include("Invalid HTTP method")
    end

    it "fails with non-HTTP URL" do
      context.set_variable("_current_node_data", { "url" => "ftp://example.com", "method" => "GET" })
      result = node.execute(context)
      expect(result).to be_failure
      expect(result.output).to include("Invalid URL")
    end

    it "fails with blank URL" do
      context.set_variable("_current_node_data", { "url" => "", "method" => "GET" })
      result = node.execute(context)
      expect(result).to be_failure
      expect(result.output).to include("Invalid URL")
    end

    it "makes a successful GET request" do
      stub_request(:get, "https://api.example.com/test")
        .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })

      context.set_variable("_current_node_data", { "url" => "https://api.example.com/test", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("success")
      expect(result.variables["status"]).to eq(200)
      expect(result.variables["body"]).to eq('{"ok":true}')
    end

    it "makes a POST request with body" do
      stub_request(:post, "https://api.example.com/data")
        .with(body: '{"name":"test"}')
        .to_return(status: 201, body: '{"id":1}')

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/data",
                             "method" => "POST",
                             "body_mode" => "json",
                             "body" => '{"name":"test"}',
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("success")
      expect(result.variables["status"]).to eq(201)
    end

    it "makes a POST request with an explicit raw body" do
      stub_request(:post, "https://api.example.com/raw")
        .with(body: "raw body")
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/raw",
                             "method" => "POST",
                             "body_mode" => "raw",
                             "body" => "raw body",
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("success")
      expect(result.variables["status"]).to eq(200)
    end

    it "routes to error port on non-2xx" do
      stub_request(:get, "https://api.example.com/fail")
        .to_return(status: 404, body: "Not Found")

      context.set_variable("_current_node_data", { "url" => "https://api.example.com/fail", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success # Node succeeds but routes to error port
      expect(result.next_port).to eq("error")
      expect(result.variables["status"]).to eq(404)
    end

    it "interpolates variables in URL" do
      stub_request(:get, "https://api.example.com/users/42")
        .to_return(status: 200, body: "{}")

      context.set_variable("user_id", "42")
      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/users/{{user_id}}",
                             "method" => "GET",
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "appends configured query params to the request URL" do
      stub_request(:get, "https://api.example.com/search?q=cats&page=2")
        .to_return(status: 200, body: "ok")

      context.set_variable("query", "cats")
      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/search",
                             "method" => "GET",
                             "params" => { "q" => "{{query}}", "page" => "2" },
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "adds bearer authorization headers" do
      stub_request(:get, "https://api.example.com/protected")
        .with(headers: { "Authorization" => "Bearer token123" })
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/protected",
                             "method" => "GET",
                             "auth_type" => "bearer",
                             "auth_bearer_token" => "token123",
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "adds basic authorization headers" do
      encoded = Base64.strict_encode64("service:secret")
      stub_request(:get, "https://api.example.com/protected")
        .with(headers: { "Authorization" => "Basic #{encoded}" })
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/protected",
                             "method" => "GET",
                             "auth_type" => "basic",
                             "auth_username" => "service",
                             "auth_password" => "secret",
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "adds api keys to the query string when configured" do
      stub_request(:get, "https://api.example.com/data?api_key=secret")
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/data",
                             "method" => "GET",
                             "auth_type" => "api_key",
                             "auth_api_key_name" => "api_key",
                             "auth_api_key_value" => "secret",
                             "auth_api_key_in" => "query",
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "adds api keys to request headers when configured" do
      stub_request(:get, "https://api.example.com/data")
        .with(headers: { "X-API-Key" => "secret" })
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/data",
                             "method" => "GET",
                             "auth_type" => "api_key",
                             "auth_api_key_name" => "X-API-Key",
                             "auth_api_key_value" => "secret",
                             "auth_api_key_in" => "header",
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "handles timeout errors" do
      stub_request(:get, "https://api.example.com/slow").to_timeout

      context.set_variable("_current_node_data", { "url" => "https://api.example.com/slow", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("timed out").or include("failed")
    end

    it "parses headers from JSON string" do
      stub_request(:get, "https://api.example.com/test")
        .with(headers: { "Authorization" => "Bearer token123" })
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/test",
                             "method" => "GET",
                             "headers" => '{"Authorization": "Bearer token123"}',
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "parses headers from hash" do
      stub_request(:get, "https://api.example.com/test")
        .with(headers: { "X-Custom" => "value" })
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/test",
                             "method" => "GET",
                             "headers" => { "X-Custom" => "value" },
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "encodes x-www-form-urlencoded request bodies" do
      stub_request(:post, "https://api.example.com/forms")
        .with(body: "name=Taylor&city=Turin", headers: { "Content-Type" => "application/x-www-form-urlencoded" })
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/forms",
                             "method" => "POST",
                             "body_mode" => "form_urlencoded",
                             "form_urlencoded_body" => { "name" => "Taylor", "city" => "Turin" },
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "encodes explicit JSON request bodies" do
      stub_request(:post, "https://api.example.com/json")
        .with(body: '{"name":"test"}', headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/json",
                             "method" => "POST",
                             "body_mode" => "json",
                             "body" => '{"name":"test"}',
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    # rubocop:disable RSpec/ExampleLength
    it "uploads multipart form-data fields and files" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("contract"),
        filename: "contract.txt",
        content_type: "text/plain",
      )
      response = double("Net::HTTPResponse", code: "200", body: "ok") # rubocop:disable RSpec/VerifiedDoubles
      allow(response).to receive(:[]).with("content-type").and_return("text/plain")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages(
        "use_ssl=" => nil,
        "open_timeout=" => nil,
        "read_timeout=" => nil,
        "write_timeout=" => nil,
      )
      captured_content_type = nil
      captured_body = nil
      captured_request = nil
      allow(http_double).to receive(:request) do |request|
        captured_request = request
        captured_content_type = request["Content-Type"]
        captured_body = request.body_stream.read
        response
      end

      context.set_variable(
        "doc",
        { "blob_id" => blob.id, "filename" => blob.filename.to_s, "content_type" => blob.content_type },
      )
      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/upload",
                             "method" => "POST",
                             "body_mode" => "multipart",
                             "multipart_form_data" => { "note" => "hello", "document" => "{{doc}}" },
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(http_double).to have_received(:request)
      expect(captured_request).not_to be_nil
      expect(captured_content_type).to include("multipart/form-data; boundary=")
      expect(captured_body).to include('name="note"', "hello", 'filename="contract.txt"')
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it "streams a binary upstream file as the request body" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("PNGDATA"),
        filename: "image.png",
        content_type: "image/png",
      )
      response = double("Net::HTTPResponse", code: "200", body: "ok") # rubocop:disable RSpec/VerifiedDoubles
      allow(response).to receive(:[]).with("content-type").and_return("text/plain")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages(
        "use_ssl=" => nil,
        "open_timeout=" => nil,
        "read_timeout=" => nil,
        "write_timeout=" => nil,
      )
      captured_content_type = nil
      captured_body = nil
      captured_request = nil
      allow(http_double).to receive(:request) do |request|
        captured_request = request
        captured_content_type = request["Content-Type"]
        captured_body = request.body_stream.read
        response
      end

      context.set_variable(
        "image_file",
        { "blob_id" => blob.id, "filename" => blob.filename.to_s, "content_type" => blob.content_type },
      )
      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/upload",
                             "method" => "POST",
                             "body_mode" => "binary",
                             "binary_source" => "{{image_file}}",
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(http_double).to have_received(:request)
      expect(captured_request).not_to be_nil
      expect(captured_content_type).to eq("image/png")
      expect(captured_body).to eq("PNGDATA")
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
    it "applies SSL verification and custom timeout settings" do
      response = double("Net::HTTPResponse", code: "200", body: "ok") # rubocop:disable RSpec/VerifiedDoubles
      allow(response).to receive(:[]).with("content-type").and_return("text/plain")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:"use_ssl=")
      allow(http_double).to receive(:"verify_mode=")
      allow(http_double).to receive(:"open_timeout=")
      allow(http_double).to receive(:"read_timeout=")
      allow(http_double).to receive(:"write_timeout=")
      allow(http_double).to receive(:request).and_return(response)

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/tuned",
                             "method" => "POST",
                             "verify_ssl" => false,
                             "connect_timeout" => 5.5,
                             "read_timeout" => 9,
                             "write_timeout" => 12,
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(http_double).to have_received(:"use_ssl=").with(true)
      expect(http_double).to have_received(:"verify_mode=").with(OpenSSL::SSL::VERIFY_NONE)
      expect(http_double).to have_received(:"open_timeout=").with(5.5)
      expect(http_double).to have_received(:"read_timeout=").with(9.0)
      expect(http_double).to have_received(:"write_timeout=").with(12.0)
    end
    # rubocop:enable RSpec/ExampleLength,RSpec/MultipleExpectations

    it "retries retryable responses before succeeding" do # rubocop:disable RSpec/ExampleLength
      first = double("Net::HTTPResponse", code: "503", body: "busy") # rubocop:disable RSpec/VerifiedDoubles
      allow(first).to receive(:[]).with("content-type").and_return("text/plain")
      allow(first).to receive(:each_header).and_return({}.each)
      second = double("Net::HTTPResponse", code: "200", body: "ok") # rubocop:disable RSpec/VerifiedDoubles
      allow(second).to receive(:[]).with("content-type").and_return("text/plain")
      allow(second).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages(
        "use_ssl=" => nil,
        "open_timeout=" => nil,
        "read_timeout=" => nil,
        "write_timeout=" => nil,
      )
      allow(http_double).to receive(:request).and_return(first, second)
      allow(Kernel).to receive(:sleep)

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/retry",
                             "method" => "GET",
                             "retry_enabled" => true,
                             "max_retries" => 1,
                             "retry_interval_ms" => 1,
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["status"]).to eq(200)
      expect(Kernel).to have_received(:sleep).with(0.001)
    end

    it "retries retryable responses without sleeping when the interval is zero" do # rubocop:disable RSpec/ExampleLength
      first = double("Net::HTTPResponse", code: "503", body: "busy") # rubocop:disable RSpec/VerifiedDoubles
      allow(first).to receive(:[]).with("content-type").and_return("text/plain")
      allow(first).to receive(:each_header).and_return({}.each)
      second = double("Net::HTTPResponse", code: "200", body: "ok") # rubocop:disable RSpec/VerifiedDoubles
      allow(second).to receive(:[]).with("content-type").and_return("text/plain")
      allow(second).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages(
        "use_ssl=" => nil,
        "open_timeout=" => nil,
        "read_timeout=" => nil,
        "write_timeout=" => nil,
      )
      allow(http_double).to receive(:request).and_return(first, second)
      allow(Kernel).to receive(:sleep)

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/retry-zero",
                             "method" => "GET",
                             "retry_enabled" => true,
                             "max_retries" => 1,
                             "retry_interval_ms" => 0,
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["status"]).to eq(200)
      expect(Kernel).not_to have_received(:sleep)
    end

    it "retries retryable transport errors before succeeding" do # rubocop:disable RSpec/ExampleLength
      response = double("Net::HTTPResponse", code: "200", body: "ok") # rubocop:disable RSpec/VerifiedDoubles
      allow(response).to receive(:[]).with("content-type").and_return("text/plain")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages(
        "use_ssl=" => nil,
        "open_timeout=" => nil,
        "read_timeout=" => nil,
        "write_timeout=" => nil,
      )
      attempts = 0
      allow(http_double).to receive(:request) do
        attempts += 1
        raise Net::OpenTimeout, "timed out" if attempts == 1

        response
      end
      allow(Kernel).to receive(:sleep)

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/retry",
                             "method" => "GET",
                             "retry_enabled" => true,
                             "max_retries" => 1,
                             "retry_interval_ms" => 1,
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["status"]).to eq(200)
      expect(attempts).to eq(2)
      expect(Kernel).to have_received(:sleep).with(0.001)
    end

    it "retries retryable transport errors without sleeping when the interval is zero" do # rubocop:disable RSpec/ExampleLength
      response = double("Net::HTTPResponse", code: "200", body: "ok") # rubocop:disable RSpec/VerifiedDoubles
      allow(response).to receive(:[]).with("content-type").and_return("text/plain")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages(
        "use_ssl=" => nil,
        "open_timeout=" => nil,
        "read_timeout=" => nil,
        "write_timeout=" => nil,
      )
      attempts = 0
      allow(http_double).to receive(:request) do
        attempts += 1
        raise Net::OpenTimeout, "timed out" if attempts == 1

        response
      end
      allow(Kernel).to receive(:sleep)

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/retry-zero",
                             "method" => "GET",
                             "retry_enabled" => true,
                             "max_retries" => 1,
                             "retry_interval_ms" => 0,
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["status"]).to eq(200)
      expect(attempts).to eq(2)
      expect(Kernel).not_to have_received(:sleep)
    end

    it "handles generic request errors" do
      stub_request(:get, "https://api.example.com/error")
        .to_raise(SocketError.new("connection refused"))

      context.set_variable("_current_node_data", { "url" => "https://api.example.com/error", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("HTTP request failed")
    end

    it "handles invalid JSON in headers gracefully" do
      stub_request(:get, "https://api.example.com/test")
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/test",
                             "method" => "GET",
                             "headers" => "not valid json {",
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "handles non-string non-hash headers" do
      stub_request(:get, "https://api.example.com/test")
        .to_return(status: 200, body: "ok")

      context.set_variable("_current_node_data", {
                             "url" => "https://api.example.com/test",
                             "method" => "GET",
                             "headers" => 42,
                           })
      result = node.execute(context)

      expect(result).to be_success
    end

    it "handles malformed URI" do
      context.set_variable("_current_node_data", { "url" => "http://[invalid", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_failure
    end

    it "strips NULL bytes from the response body" do
      binary_body = "text\x00with\x00nulls"
      response = instance_double(Net::HTTPOK, code: "200", body: binary_body)
      allow(response).to receive(:[]).with("content-type").and_return("text/plain")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages("use_ssl=": nil,
                                             "open_timeout=": nil, "read_timeout=": nil,
                                             request: response,)

      context.set_variable("_current_node_data", { "url" => "http://example.com/text", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["body"]).not_to include("\x00")
      expect(result.variables["body"]).to eq("textwithnulls")
    end

    it "stores image responses as Active Storage attachments" do
      jpeg_bytes = "\xFF\xD8\xFF\xE0\x00\x10JFIF".b # minimal JPEG-like binary
      response = instance_double(Net::HTTPOK, code: "200", body: jpeg_bytes)
      allow(response).to receive(:[]).with("content-type").and_return("image/jpeg")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages("use_ssl=": nil,
                                             "open_timeout=": nil, "read_timeout=": nil,
                                             request: response,)

      context.set_variable("_current_node_data", { "url" => "http://example.com/photo.jpg", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["body"]).to be_a(Hash)
      expect(result.variables["body"]).to include("blob_id", "filename", "content_type", "byte_size")
      expect(result.variables["body"]["content_type"]).to eq("image/jpeg")
      expect(run.files).to be_attached
    end

    it "stores PDF responses as Active Storage attachments" do
      pdf_bytes = "%PDF-1.4 fake".b
      response = instance_double(Net::HTTPOK, code: "200", body: pdf_bytes)
      allow(response).to receive(:[]).with("content-type").and_return("application/pdf")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages("use_ssl=": nil,
                                             "open_timeout=": nil, "read_timeout=": nil,
                                             request: response,)

      context.set_variable("_current_node_data", { "url" => "http://example.com/doc.pdf", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["body"]).to include("blob_id", "filename", "content_type")
      expect(result.variables["body"]["content_type"]).to eq("application/pdf")
    end

    it "keeps text content types as inline strings" do
      stub_request(:get, "https://api.example.com/data")
        .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })

      context.set_variable("_current_node_data", { "url" => "https://api.example.com/data", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["body"]).to eq('{"ok":true}')
    end

    it "truncates oversized text response bodies" do
      large_body = "x" * 100
      stub_const("Missions::Nodes::HttpRequest::MAX_BODY_SIZE", 50)
      response = instance_double(Net::HTTPOK, code: "200", body: large_body)
      allow(response).to receive(:[]).with("content-type").and_return("text/plain")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages("use_ssl=": nil,
                                             "open_timeout=": nil, "read_timeout=": nil,
                                             request: response,)

      context.set_variable("_current_node_data", { "url" => "http://example.com/api", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["body"]).to be_a(String)
      expect(result.variables["body"].bytesize).to eq(50)
    end

    it "truncates oversized binary responses before storing" do
      large_binary = "\xFF" * 100
      stub_const("Missions::Nodes::HttpRequest::MAX_BODY_SIZE", 50)
      response = instance_double(Net::HTTPOK, code: "200", body: large_binary)
      allow(response).to receive(:[]).with("content-type").and_return("image/png")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages("use_ssl=": nil,
                                             "open_timeout=": nil, "read_timeout=": nil,
                                             request: response,)

      context.set_variable("_current_node_data", { "url" => "http://example.com/big.png", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["body"]["byte_size"]).to eq(50)
    end

    it "generates a fallback filename for URLs with no path" do
      png_bytes = "\x89PNG".b
      response = instance_double(Net::HTTPOK, code: "200", body: png_bytes)
      allow(response).to receive(:[]).with("content-type").and_return("image/png")
      allow(response).to receive(:each_header).and_return({}.each)
      http_double = double("Net::HTTP") # rubocop:disable RSpec/VerifiedDoubles
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive_messages("use_ssl=": nil,
                                             "open_timeout=": nil, "read_timeout=": nil,
                                             request: response,)

      context.set_variable("_current_node_data", { "url" => "http://example.com/", "method" => "GET" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["body"]["filename"]).to match(/\Aresponse_\d+\.png\z/)
    end
  end

  describe "private helpers" do
    it "skips blank keys and nil values when resolving request pairs" do
      context.set_variable("present", "ok")

      resolved = node.send(:resolve_pairs, context, {
                             "" => "ignored",
                             "missing" => "{{unknown}}",
                             "present" => "{{present}}",
                           })

      expect(resolved).to eq({ "present" => "ok" })
    end

    it "returns raw complex values from resolve_value" do
      value = { "blob_id" => 1, "filename" => "file.txt" }

      expect(node.send(:resolve_value, context, value)).to eq(value)
    end

    it "stringifies complex values as JSON" do
      expect(node.send(:stringify_value, { "enabled" => true })).to eq('{"enabled":true}')
    end

    it "skips empty authorization inputs" do
      headers = {}
      params = {}

      node.send(:apply_authorization!, headers, params, context, {
                  "auth_type" => "bearer",
                  "auth_bearer_token" => "",
                })
      node.send(:apply_authorization!, headers, params, context, {
                  "auth_type" => "basic",
                  "auth_username" => "",
                  "auth_password" => "",
                })
      node.send(:apply_authorization!, headers, params, context, {
                  "auth_type" => "api_key",
                  "auth_api_key_name" => "",
                  "auth_api_key_value" => "secret",
                })

      expect(headers).to eq({})
      expect(params).to eq({})
    end

    it "leaves content types unset for empty JSON, raw, and form payloads" do
      json_headers = {}
      raw_headers = {}
      form_headers = {}

      json_payload = node.send(:build_json_payload, json_headers, context, { "body" => "" })
      raw_payload = node.send(:build_raw_payload, raw_headers, context, {
                                "body" => "raw body",
                                "body_content_type" => "",
                              })
      form_payload = node.send(:build_form_urlencoded_payload, form_headers, context, {
                                 "form_urlencoded_body" => {},
                               })

      expect([json_headers, raw_headers, form_headers]).to eq([{}, {}, {}])
      expect([json_payload.body, raw_payload.body, form_payload.body]).to eq(["", "raw body", ""])
    end

    it "applies custom raw content types when present" do
      headers = {}

      payload = node.send(:build_raw_payload, headers, context, {
                            "body" => "raw body",
                            "body_content_type" => "text/plain",
                          })

      expect(headers).to eq({ "Content-Type" => "text/plain" })
      expect(payload.body).to eq("raw body")
    end

    it "returns empty payloads for invalid binary uploads" do
      context.set_variable("missing_file", { "blob_id" => -1, "filename" => "ghost.txt" })

      missing_source_payload = node.send(:build_binary_payload, {}, context, { "binary_source" => "plain" })
      missing_blob_payload = node.send(:build_binary_payload, {}, context, { "binary_source" => "{{missing_file}}" })

      expect(missing_source_payload.body).to be_nil
      expect(missing_source_payload.body_stream).to be_nil
      expect(missing_blob_payload.body).to be_nil
      expect(missing_blob_payload.body_stream).to be_nil
    end

    it "skips empty multipart parts and missing multipart blobs" do
      tempfile = Tempfile.new(["multipart", ".txt"])
      tempfile.binmode

      node.send(:append_multipart_part, tempfile, "boundary", "", "value")
      node.send(:append_multipart_part, tempfile, "boundary", "field", nil)
      node.send(:append_multipart_file, tempfile, "boundary", "file", { "blob_id" => -1, "filename" => "ghost" })

      expect(tempfile.size).to eq(0)
    ensure
      tempfile.close
      tempfile.unlink
    end

    it "applies and rewinds payloads safely when they are absent" do
      request = Net::HTTP::Post.new("/")

      expect { node.send(:apply_payload!, request, nil) }.not_to raise_error
      expect { node.send(:rewind_payload!, nil) }.not_to raise_error
      expect(request.body).to be_nil
    end

    it "preserves existing headers and ignores blank new values" do
      headers = { "Content-Type" => "text/plain" }

      node.send(:set_header_if_missing, headers, "X-Test", "")
      node.send(:set_header_if_missing, headers, "content-type", "application/json")

      expect(headers).to eq({ "Content-Type" => "text/plain" })
    end

    it "falls back to defaults for invalid retry counts" do
      expect(node.send(:retry_count, 0)).to eq(described_class::DEFAULT_MAX_RETRIES)
      expect(node.send(:retry_count, "invalid")).to eq(described_class::DEFAULT_MAX_RETRIES)
    end

    it "defaults invalid body modes to none" do
      expect(node.send(:resolved_body_mode, {
                         "body_mode" => "legacy_json",
                         "body" => '{"ok":true}',
                         "headers" => { "Content-Type" => "application/json" },
                       })).to eq("none")
    end

    it "ignores IOErrors when cleaning up tempfiles" do
      failing_tempfile = Class.new do
        attr_reader :unlinked

        def closed? = false

        def close = raise IOError, "boom"

        def unlink = @unlinked = true
      end.new

      closed_tempfile = Class.new do
        def closed? = true
      end.new

      expect { node.send(:cleanup_tempfiles, [failing_tempfile, closed_tempfile]) }.not_to raise_error
      expect(failing_tempfile.unlinked).to be_nil
    end
  end
end
