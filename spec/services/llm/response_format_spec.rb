# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::ResponseFormat do
  describe ".normalize_format" do
    it "defaults blank values to text" do
      expect(described_class.normalize_format(nil)).to eq("text")
    end
  end

  describe ".normalize_schema" do
    it "normalizes nil, strings, hashes, and hash-like objects" do
      wrapper = Struct.new(:payload) do
        def to_h = payload
      end.new({ type: "object" })

      expect(described_class.normalize_schema(nil)).to eq({})
      expect(described_class.normalize_schema("   ")).to eq({})
      expect(described_class.normalize_schema('{"type":"object"}')).to eq({ "type" => "object" })
      expect(described_class.normalize_schema({ type: "array" })).to eq({ "type" => "array" })
      expect(described_class.normalize_schema(wrapper)).to eq({ "type" => "object" })
    end

    it "rejects invalid or non-object schemas" do
      expect { described_class.normalize_schema("not-json") }.to raise_error(
        described_class::InvalidSchemaError,
        /valid JSON/,
      )
      expect { described_class.normalize_schema("[]") }.to raise_error(
        described_class::InvalidSchemaError,
        /JSON object/,
      )
      expect { described_class.normalize_schema(Object.new) }.to raise_error(
        described_class::InvalidSchemaError,
        /JSON object/,
      )
    end
  end

  describe ".apply_to_chat" do
    it "does nothing for text responses" do
      chat = Class.new do
        attr_reader :params_called, :schema_called

        def with_params(**)
          @params_called = true
        end

        def with_schema(*)
          @schema_called = true
        end
      end.new

      described_class.apply_to_chat(chat:, response_format: "text", response_schema: nil)

      expect(chat.params_called).to be_nil
      expect(chat.schema_called).to be_nil
    end

    it "merges JSON object response params with existing chat params" do
      chat = Class.new do
        attr_reader :params

        def initialize
          @params = { top_p: 0.9 }
        end

        def with_params(**params)
          @params = params
        end
      end.new

      described_class.apply_to_chat(chat:, response_format: "json_object", response_schema: nil)

      expect(chat.params).to eq(top_p: 0.9, response_format: { type: "json_object" })
    end

    it "applies JSON object response params when no params reader exists" do
      chat = Class.new do
        attr_reader :applied_params

        def with_params(**params)
          @applied_params = params
        end
      end.new

      described_class.apply_to_chat(chat:, response_format: "json_object", response_schema: nil)

      expect(chat.applied_params).to eq(response_format: { type: "json_object" })
    end

    it "ignores existing params that cannot be converted to a hash" do
      chat = Class.new do
        attr_reader :applied_params

        def params = 123

        def with_params(**params)
          @applied_params = params
        end
      end.new

      described_class.apply_to_chat(chat:, response_format: "json_object", response_schema: nil)

      expect(chat.applied_params).to eq(response_format: { type: "json_object" })
    end

    it "applies JSON schema through RubyLLM's schema API" do
      chat = instance_double(Chat)
      schema = { "type" => "object" }
      allow(chat).to receive(:with_schema)

      described_class.apply_to_chat(chat:, response_format: "json_schema", response_schema: schema)

      expect(chat).to have_received(:with_schema).with(schema)
    end
  end

  describe ".schema_json and .schema_summary" do
    it "formats schema JSON" do
      schema = { type: "object", properties: { answer: { type: "string" } } }

      expect(described_class.schema_json(schema)).to include("answer")
      expect(described_class.schema_json("not-json")).to eq("not-json")
    end

    it "summarizes schemas" do
      schema = { type: "object", properties: { answer: { type: "string" } } }

      expect(described_class.schema_summary({})).to eq("No schema")
      expect(described_class.schema_summary({ "type" => "array" })).to eq("array schema")
      expect(described_class.schema_summary(schema)).to eq("object schema (1 field)")
      expect(described_class.schema_summary(Object.new)).to eq("Invalid schema")
    end
  end
end
