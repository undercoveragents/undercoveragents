# frozen_string_literal: true

# == Schema Information
#
# Table name: tools_rag_flows
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  custom_instructions :text
#  distance_method     :string           default("cosine"), not null
#  document_fields     :jsonb            not null
#  max_distance        :float            default(0.8)
#  results_limit       :integer          default(10), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  rag_flow_id         :bigint           not null
#
# Indexes
#
#  index_tools_rag_flows_on_rag_flow_id  (rag_flow_id)
#
# Foreign Keys
#
#  fk_rails_...  (rag_flow_id => rag_flows.id)
#
require "rails_helper"

RSpec.describe Tools::RagFlow do
  describe "tool designer metadata" do
    it "exposes editable attributes and notes for the tool designer" do
      expect(described_class.tool_designer_editable_attributes).to include("rag_flow_id", "results_limit")
      expect(described_class.tool_designer_notes).to include(
        "Use list_resources(kind: \"rag_flows\") to resolve rag_flow_id values.",
      )
    end

    it "declares the field hint and resource kind metadata" do
      expect(described_class.tool_designer_field_hints).to eq(
        "rag_flow_id" => {
          "resource_kind" => "rag_flows",
        },
      )
      expect(described_class.tool_designer_resource_kinds).to eq(
        [{
          "kind" => "rag_flows",
          "title" => "RAG Flows",
          "model_name" => "RagFlow",
          "scope" => "operation_owned",
        }],
      )
    end
  end

  describe "rag_flow accessor" do
    it "returns the rag_flow by id" do
      flow = create(:rag_flow, :with_steps)
      rf = build(:tools_rag_flow, rag_flow: flow)
      expect(rf.rag_flow).to eq(flow)
    end
  end

  describe "persistence" do
    it "#id returns the backing tool's id" do
      rf = create(:tools_rag_flow)
      expect(rf.id).to eq(rf._tool_record.id)
    end

    it "#reload refreshes attributes from the database" do
      rf = create(:tools_rag_flow)
      rf.results_limit
      rf._tool_record.update_column(:configuration, rf._tool_record.configuration.merge("results_limit" => 99)) # rubocop:disable Rails/SkipsModelValidations
      rf.reload
      expect(rf.results_limit).to eq(99)
    end

    it "== compares by id" do
      rf1 = create(:tools_rag_flow)
      rf2 = create(:tools_rag_flow)
      expect(rf1).not_to eq(rf2)
      expect(rf1.reload).to eq(rf1)
    end

    it "#id returns nil when no _tool_record is set" do
      rf = build(:tools_rag_flow)
      expect(rf.id).to be_nil
    end

    it "== returns false for non-RagFlow objects" do
      rf = create(:tools_rag_flow)
      expect(rf == "other").to be(false)
    end
  end

  describe "#rag_flow" do
    it "returns nil when rag_flow_id is blank" do
      rf = build(:tools_rag_flow, rag_flow_id: nil)
      expect(rf.rag_flow).to be_nil
    end

    it "re-fetches the rag flow when the cached instance is explicitly nil" do
      flow = create(:rag_flow, :with_steps)
      rf = described_class.new(rag_flow_id: flow.id)

      rf.rag_flow = nil
      rf.rag_flow_id = flow.id

      expect(rf.rag_flow).to eq(flow)
    end

    it "accepts nil assignment" do
      rf = build(:tools_rag_flow)
      rf.rag_flow = nil
      expect(rf.rag_flow_id).to be_nil
    end

    it "returns cached rag_flow on repeated access" do
      flow = create(:rag_flow, :with_steps)
      rf = build(:tools_rag_flow, rag_flow: flow)
      first = rf.rag_flow
      expect(rf.rag_flow).to be(first)
      expect(first).to eq(flow)
    end

    it "re-fetches the rag flow when rag_flow_id changes" do
      first_flow = create(:rag_flow, :with_steps)
      second_flow = create(:rag_flow, :with_steps)
      rf = build(:tools_rag_flow, rag_flow: first_flow)

      rf.rag_flow
      rf.rag_flow_id = second_flow.id

      expect(rf.rag_flow).to eq(second_flow)
    end
  end

  describe "#update_rag_flow_id_from_cache" do
    it "does nothing when the cache has not been initialized" do
      flow = create(:rag_flow, :with_steps)
      rf = described_class.new(rag_flow_id: flow.id)

      expect { rf.send(:update_rag_flow_id_from_cache) }.not_to(change(rf, :rag_flow_id))
    end

    it "clears rag_flow_id when the cache is explicitly nil" do
      rf = described_class.new(rag_flow_id: 123)
      rf.instance_variable_set(:@rag_flow_cache, nil)

      rf.send(:update_rag_flow_id_from_cache)

      expect(rf.rag_flow_id).to be_nil
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:distance_method) }
    it { is_expected.to validate_presence_of(:results_limit) }
    it { is_expected.to validate_inclusion_of(:distance_method).in_array(Tools::RagSearchable::DISTANCE_METHODS) }
    it { is_expected.to validate_length_of(:custom_instructions).is_at_most(10_000) }

    it "validates results_limit is positive integer" do
      rf = build(:tools_rag_flow, results_limit: 0)
      expect(rf).not_to be_valid
    end

    it "validates results_limit does not exceed maximum" do
      rf = build(:tools_rag_flow, results_limit: 101)
      expect(rf).not_to be_valid
    end

    it "validates max_distance range" do
      rf = build(:tools_rag_flow, max_distance: 3.0)
      expect(rf).not_to be_valid
    end

    it "allows nil max_distance" do
      rf = build(:tools_rag_flow, max_distance: nil)
      rf.rag_flow = create(:rag_flow, :with_steps)
      expect(rf).to be_valid
    end

    it "validates rag_flow must have a SQL database storage step" do
      flow = create(:rag_flow) # no steps
      rf = build(:tools_rag_flow, rag_flow: flow)
      expect(rf).not_to be_valid
      expect(rf.errors[:rag_flow]).to include("must have a SQL Database Storage step configured")
    end

    it "validates rag_flow must have an LLM embedder step" do
      flow = create(:rag_flow)
      # Add only storage step, no embedding
      create(:rag_step, rag_flow: flow, stage: "storage",
                        module_type: "sql_database_storage",
                        configuration: {
                          "connector_id" => nil, "documents_table" => "docs",
                          "chunks_table" => "chunks", "content_field" => "content",
                          "embedding_field" => "embedding",
                          "document_reference_field" => "document_id",
                          "pre_load_action" => "none",
                        },)

      rf = build(:tools_rag_flow, rag_flow: flow)
      expect(rf).not_to be_valid
      expect(rf.errors[:rag_flow]).to include("must have an LLM Embedder step configured")
    end

    it "is valid with a fully configured rag flow" do
      rf = create(:tools_rag_flow)
      expect(rf).to be_valid
    end
  end

  describe "#distance_operator" do
    it "returns cosine operator for cosine" do
      rf = build(:tools_rag_flow, distance_method: "cosine")
      expect(rf.distance_operator).to eq("<=>")
    end

    it "returns L2 operator for l2" do
      rf = build(:tools_rag_flow, distance_method: "l2")
      expect(rf.distance_operator).to eq("<->")
    end

    it "returns inner product operator" do
      rf = build(:tools_rag_flow, distance_method: "inner_product")
      expect(rf.distance_operator).to eq("<#>")
    end
  end

  describe "#selected_document_fields" do
    it "returns destination column names (values) from explicit metadata_field_mappings" do
      rf = create(:tools_rag_flow)
      step = rf.rag_flow.step_for(:storage)
      step.update!(configuration: step.configuration.merge("metadata_field_mappings" => { "source_title" => "title",
                                                                                          "page_url" => "url", }))
      expect(rf.selected_document_fields).to contain_exactly("title", "url")
    end

    it "deduplicates destination columns when explicit mappings have repeated values" do
      rf = create(:tools_rag_flow)
      step = rf.rag_flow.step_for(:storage)
      step.update!(configuration: step.configuration.merge("metadata_field_mappings" => { "a" => "title",
                                                                                          "b" => "title", }))
      expect(rf.selected_document_fields).to eq(["title"])
    end

    it "falls back to source metadata_columns when metadata_field_mappings is empty (auto-mapping)" do
      rf = create(:tools_rag_flow)
      storage_step = rf.rag_flow.step_for(:storage)
      storage_step.update!(configuration: storage_step.configuration.merge("metadata_field_mappings" => {}))
      source_step = rf.rag_flow.step_for(:source)
      source_step.update!(configuration: source_step.configuration.merge("metadata_columns" => ["title", "description",
                                                                                                "url",]))
      expect(rf.selected_document_fields).to contain_exactly("title", "description", "url")
    end

    it "returns empty array when auto-mapping and source has no metadata_columns" do
      rf = create(:tools_rag_flow)
      storage_step = rf.rag_flow.step_for(:storage)
      storage_step.update!(configuration: storage_step.configuration.merge("metadata_field_mappings" => {}))
      source_step = rf.rag_flow.step_for(:source)
      source_step.update!(configuration: source_step.configuration.merge("metadata_columns" => []))
      expect(rf.selected_document_fields).to eq([])
    end

    it "returns empty array when storage step is nil" do
      rf = build(:tools_rag_flow)
      allow(rf).to receive(:storage_step).and_return(nil)
      expect(rf.selected_document_fields).to eq([])
    end
  end

  describe "#effective_instructions" do
    it "returns custom instructions when present" do
      rf = build(:tools_rag_flow, custom_instructions: "Search my knowledge base")
      expect(rf.effective_instructions).to eq("Search my knowledge base")
    end

    it "returns default prompt when custom instructions are blank" do
      rf = build(:tools_rag_flow, custom_instructions: nil)
      expect(rf.effective_instructions).to eq(Tools::RagSearchable::DEFAULT_TOOL_PROMPT)
    end
  end

  describe "delegated accessors from rag flow" do
    let(:rag_flow) { create(:tools_rag_flow) }

    it "delegates sql_database to storage step" do
      expect(rag_flow.sql_database).to eq(rag_flow.storage_step.connector)
    end

    it "delegates chunks_table to storage step" do
      expect(rag_flow.chunks_table).to eq(rag_flow.storage_step.chunks_table)
    end

    it "delegates documents_table to storage step" do
      expect(rag_flow.documents_table).to eq(rag_flow.storage_step.documents_table)
    end

    it "delegates embedding_field to storage step" do
      expect(rag_flow.embedding_field).to eq(rag_flow.storage_step.embedding_field)
    end

    it "delegates chunk_content_field to storage step content_field" do
      expect(rag_flow.chunk_content_field).to eq(rag_flow.storage_step.content_field)
    end

    it "delegates document_reference_field to storage step" do
      expect(rag_flow.document_reference_field).to eq(rag_flow.storage_step.document_reference_field)
    end

    it "delegates embedding_model_id to embedding step" do
      expect(rag_flow.embedding_model_id).to eq(rag_flow.embedding_step.model_id)
    end

    it "delegates llm_connector to embedding step" do
      expect(rag_flow.llm_connector).to eq(rag_flow.embedding_step.llm_connector)
    end

    context "when steps are not configured" do
      before do
        allow(rag_flow).to receive_messages(storage_step: nil, embedding_step: nil)
      end

      it "returns nil for sql_database" do
        expect(rag_flow.sql_database).to be_nil
      end

      it "returns nil for chunks_table" do
        expect(rag_flow.chunks_table).to be_nil
      end

      it "returns nil for documents_table" do
        expect(rag_flow.documents_table).to be_nil
      end

      it "returns nil for embedding_field" do
        expect(rag_flow.embedding_field).to be_nil
      end

      it "returns nil for chunk_content_field" do
        expect(rag_flow.chunk_content_field).to be_nil
      end

      it "returns nil for document_reference_field" do
        expect(rag_flow.document_reference_field).to be_nil
      end

      it "returns nil for embedding_model_id" do
        expect(rag_flow.embedding_model_id).to be_nil
      end

      it "returns nil for llm_connector" do
        expect(rag_flow.llm_connector).to be_nil
      end
    end
  end

  describe "#storage_step" do
    it "returns the storage module from the rag flow" do
      rf = create(:tools_rag_flow)
      expect(rf.storage_step).to be_a(RagSteps::SqlDatabaseStorage)
    end

    it "returns nil when rag_flow is nil" do
      rf = build(:tools_rag_flow)
      allow(rf).to receive(:rag_flow).and_return(nil)
      expect(rf.storage_step).to be_nil
    end
  end

  describe "#embedding_step" do
    it "returns the embedding module from the rag flow" do
      rf = create(:tools_rag_flow)
      expect(rf.embedding_step).to be_a(RagSteps::LlmEmbedder)
    end

    it "returns nil when rag_flow is nil" do
      rf = build(:tools_rag_flow)
      allow(rf).to receive(:rag_flow).and_return(nil)
      expect(rf.embedding_step).to be_nil
    end
  end

  describe ".type_key" do
    it "returns rag_flow" do
      expect(described_class.type_key).to eq("rag_flow")
    end
  end

  describe ".type_label" do
    it "returns RAG" do
      expect(described_class.type_label).to eq("RAG")
    end
  end

  describe ".type_icon" do
    it "returns the correct icon class" do
      expect(described_class.type_icon).to eq("fa-solid fa-diagram-project")
    end
  end

  describe ".permitted_params" do
    it "extracts rag_flow params" do
      params = ActionController::Parameters.new(
        rag_flow: {
          rag_flow_id: "1",
          custom_instructions: "Search docs",
          distance_method: "cosine",
          max_distance: "0.5",
          results_limit: "20",
          document_fields: ["title", "url"],
        },
      )
      result = described_class.permitted_params(params)
      expect(result[:rag_flow_id]).to eq("1")
      expect(result[:distance_method]).to eq("cosine")
    end
  end

  describe ".build_from_params" do
    it "creates a new instance from params" do
      flow = create(:rag_flow, :with_steps)
      params = ActionController::Parameters.new(
        rag_flow: {
          rag_flow_id: flow.id.to_s,
          distance_method: "cosine",
          max_distance: "0.7",
          results_limit: "15",
          document_fields: ["title"],
        },
      )
      rf = described_class.build_from_params(params)
      expect(rf).to be_a(described_class)
      expect(rf.rag_flow_id).to eq(flow.id)
    end
  end
end
