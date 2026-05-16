# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::EmbeddingService do
  let(:connector) { create(:connector, :llm_provider, :enabled) }
  let(:configurator_double) { instance_double(Connectors::LlmProvider, build_context: {}) }
  let(:service) { described_class.new(connector:, model: "text-embedding-3-small") }

  before do
    allow(connector).to receive(:configurator).and_return(configurator_double)
  end

  describe "#embed" do
    it "calls RubyLLM.embed with the correct parameters" do
      vector = Array.new(1536) { rand }
      response_double = instance_double(RubyLLM::Embedding, vectors: [vector])

      allow(RubyLLM).to receive(:embed).and_return(response_double)

      result = service.embed("Hello world")

      expect(result).to eq(vector)
      expect(RubyLLM).to have_received(:embed).with(
        "Hello world",
        model: "text-embedding-3-small",
        context: {},
      )
    end

    it "raises ArgumentError when text is blank" do
      expect { service.embed("") }.to raise_error(ArgumentError, "text cannot be blank")
      expect { service.embed(nil) }.to raise_error(ArgumentError, "text cannot be blank")
    end
  end
end
