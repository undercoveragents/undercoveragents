# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::PluginSystem::Definition do
  subject(:definition) { described_class.new("test_definition") }

  describe "#initialize" do
    it "sets default values" do # rubocop:disable RSpec/MultipleExpectations
      expect(definition.identifier).to eq("test_definition")
      expect(definition.version).to eq("0.1.0")
      expect(definition.author).to eq("Undercover Agents")
      expect(definition.icon).to eq("fa-solid fa-puzzle-piece")
      expect(definition.category).to eq([:general])
      expect(definition.description).to eq("")
    end
  end

  describe "attribute accessors" do
    it "allows setting and reading all attributes" do
      definition.name "Test"
      definition.version "2.0.0"
      definition.author "Author"
      definition.description "A description"
      definition.icon "fa-solid fa-test"
      definition.category [:rag_chunking]
      definition.add_rag_chunker("RagSteps::ParagraphChunker")
      definition.root_path = Pathname.new("/tmp")

      expect(definition.name).to eq("Test")
      expect(definition.description).to eq("A description")
      expect(definition.root_path).to eq(Pathname.new("/tmp"))
      expect(definition.rag_step_entry_points.first[:class_name]).to eq("RagSteps::ParagraphChunker")
    end
  end

  describe "RAG entry points" do
    it "supports multiple rag categories and exposes rag_step_plugin?" do
      definition.category [:rag_chunking, :rag_embedding]
      definition.add_rag_chunker("RagSteps::FixedSizeChunker")
      definition.add_rag_embedding("RagSteps::LlmEmbedder")

      expect(definition.rag_step_plugin?).to be(true)
      expect(definition.rag_step_entry_points.pluck(:stage)).to contain_exactly(:chunking, :embedding)
    end

    it "normalizes category values and supports add_rag_source alias" do
      definition.category = "rag_input"
      definition.add_rag_source("RagSteps::SqlDatabaseSource")

      expect(definition.category).to eq([:rag_input])
      expect(definition.rag_step_entry_points.first[:stage]).to eq(:source)
    end

    it "detects rag-step plugins from categories even before entry points are added" do
      definition.category [:rag_embedding]

      expect(definition.rag_step_plugin?).to be(true)
      expect(definition.rag_step_entry_points).to be_empty
    end
  end

  describe "tool entry points" do
    it "supports tool entry points and exposes tool_plugin?" do
      definition.category [:tool]
      definition.add_tool("Tools::SqlQuery")

      expect(definition.tool_plugin?).to be(true)
      expect(definition.tool_entry_points).to eq([{ category: :tool, class_name: "Tools::SqlQuery" }])
    end
  end

  describe "#freeze! and #frozen?" do
    it "marks the definition as frozen" do
      expect(definition.frozen?).to be(false)
      definition.freeze!
      expect(definition.frozen?).to be(true)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      definition.name = "My Plugin"
      definition.category [:rag_chunking]
      definition.add_rag_chunker("RagSteps::FixedSizeChunker")
      hash = definition.to_h
      expect(hash[:identifier]).to eq("test_definition")
      expect(hash[:name]).to eq("My Plugin")
      expect(hash[:category]).to eq([:rag_chunking])
      expect(hash[:entry_points].first[:stage]).to eq(:chunking)
    end
  end

  describe "#engine_module_name" do
    it "returns a camelized engine module name" do
      expect(definition.engine_module_name).to eq("UndercoverAgents::Plugins::TestDefinitionEngine")
    end
  end
end
