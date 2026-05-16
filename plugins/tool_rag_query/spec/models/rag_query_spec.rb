# frozen_string_literal: true

# == Schema Information
#
# Table name: tools_rag_queries
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  chunk_content_field      :string           default("content"), not null
#  chunks_table             :string           not null
#  custom_instructions      :text
#  discovered_schema        :jsonb            not null
#  distance_method          :string           default("cosine"), not null
#  document_fields          :jsonb            not null
#  document_reference_field :string           default("document_id"), not null
#  documents_table          :string           not null
#  embedding_field          :string           default("embedding"), not null
#  max_distance             :float            default(0.8)
#  results_limit            :integer          default(10), not null
#  schema_discovered_at     :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  connector_id             :bigint           not null
#  embedding_model_id       :string
#  llm_connector_id         :bigint
#
# Indexes
#
#  index_tools_rag_queries_on_connector_id      (connector_id)
#  index_tools_rag_queries_on_llm_connector_id  (llm_connector_id)
#
# Foreign Keys
#
#  fk_rails_...  (connector_id => connectors.id)
#  fk_rails_...  (llm_connector_id => connectors.id)
#
require "rails_helper"

RSpec.describe Tools::RagQuery do
  describe "tool designer metadata" do
    it "declares plugin-owned field hints" do
      expect(described_class.tool_designer_field_hints).to eq(
        "connector_id" => { "resource_kind" => "sql_database_connectors" },
        "llm_connector_id" => { "resource_kind" => "llm_connectors" },
        "embedding_model_id" => {
          "resource_kind" => "models",
          "note" => "Pass connector_id: llm_connector_id.",
        },
      )
    end

    it "declares plugin-owned state entries" do
      expect(described_class.tool_designer_state_attributes).to include(
        hash_including("label" => "Schema discovered at", "method" => "schema_discovered_at"),
        hash_including("label" => "Discovered tables", "method" => "all_discovered_table_names"),
      )
    end
  end

  describe "connector accessors" do
    it "returns the connector by id" do
      sql_connector = create(:connector, :sql_database)
      rq = build(:tools_rag_query, connector: sql_connector)
      expect(rq.connector).to eq(sql_connector)
    end

    it "returns nil when connector_id is blank" do
      rq = build(:tools_rag_query, connector: nil)
      expect(rq.connector).to be_nil
    end
  end

  describe "persistence" do
    it "#id returns the backing tool's id" do
      rq = create(:tools_rag_query)
      expect(rq.id).to eq(rq._tool_record.id)
    end

    it "#reload refreshes attributes from the database" do
      rq = create(:tools_rag_query)
      rq._tool_record.update_column(:configuration, rq._tool_record.configuration.merge("results_limit" => 7)) # rubocop:disable Rails/SkipsModelValidations
      rq.reload
      expect(rq.results_limit).to eq(7)
    end

    it "#reload returns self when no _tool_record is set" do
      rq = build(:tools_rag_query)
      expect(rq.reload).to be(rq)
    end

    it "== compares by id" do
      rq1 = create(:tools_rag_query)
      rq2 = create(:tools_rag_query)
      expect(rq1).not_to eq(rq2)
      expect(rq1.reload).to eq(rq1)
    end

    it "#id returns nil when no _tool_record is set" do
      rq = build(:tools_rag_query)
      expect(rq.id).to be_nil
    end

    it "raises when save! is called without a backing tool record" do
      expect { build(:tools_rag_query).save! }.to raise_error("No _tool_record set")
    end

    it "== returns false for non-RagQuery objects" do
      rq = create(:tools_rag_query)
      expect(rq == "other").to be(false)
    end

    it "== falls through to object identity for unsaved objects" do
      rq1 = build(:tools_rag_query)
      rq2 = build(:tools_rag_query)
      expect(rq1).not_to eq(rq2)
      myself = rq1
      expect(rq1).to eq(myself)
    end
  end

  describe "#connector" do
    it "returns nil when connector_id is blank" do
      rq = build(:tools_rag_query, connector_id: nil)
      expect(rq.connector).to be_nil
    end

    it "clears connector_id when assigned nil" do
      rq = build(:tools_rag_query)
      rq.connector = nil
      expect(rq.connector_id).to be_nil
    end

    it "clears llm_connector_id when llm_connector= nil" do
      rq = build(:tools_rag_query)
      rq.llm_connector = nil
      expect(rq.llm_connector_id).to be_nil
    end

    it "returns cached connector on repeated access" do
      sql_connector = create(:connector, :sql_database)
      rq = build(:tools_rag_query, connector: sql_connector)
      first = rq.connector
      second = rq.connector
      expect(second).to be(first)
    end

    it "re-fetches connector when connector_id changes" do
      sql_connector1 = create(:connector, :sql_database)
      sql_connector2 = create(:connector, :sql_database)
      rq = build(:tools_rag_query, connector: sql_connector1)
      rq.connector # warm cache
      rq.connector_id = sql_connector2.id
      expect(rq.connector).to eq(sql_connector2)
    end
  end

  describe "#llm_connector" do
    it "returns nil when llm_connector_id is blank" do
      rq = build(:tools_rag_query, llm_connector_id: nil)
      expect(rq.llm_connector).to be_nil
    end

    it "loads llm_connector by id when the cache is cold" do
      llm = create(:connector, :llm_provider, :enabled)
      rq = build(:tools_rag_query, llm_connector: nil, llm_connector_id: llm.id, embedding_model_id: "embed-v1")

      expect(rq.llm_connector).to eq(llm)
    end

    it "returns cached llm_connector on repeated access" do
      llm = create(:connector, :llm_provider, :enabled)
      rq = build(:tools_rag_query, llm_connector: llm, embedding_model_id: "embed-v1")
      first = rq.llm_connector
      second = rq.llm_connector
      expect(second).to be(first)
    end

    it "re-fetches llm_connector when llm_connector_id changes" do
      llm1 = create(:connector, :llm_provider, :enabled)
      llm2 = create(:connector, :llm_provider, :enabled)
      rq = build(:tools_rag_query, llm_connector: llm1, embedding_model_id: "embed-v1")
      rq.llm_connector # warm cache
      rq.llm_connector_id = llm2.id
      expect(rq.llm_connector).to eq(llm2)
    end
  end

  describe "#llm_connector_must_be_llm_provider with deleted connector" do
    it "adds an error when llm_connector_id is set but connector was deleted" do
      rq = build(:tools_rag_query, llm_connector_id: 999_999_999, embedding_model_id: "embed-v1")
      rq.valid?
      expect(rq.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:chunks_table) }
    it { is_expected.to validate_presence_of(:documents_table) }
    it { is_expected.to validate_presence_of(:chunk_content_field) }
    it { is_expected.to validate_presence_of(:embedding_field) }
    it { is_expected.to validate_presence_of(:document_reference_field) }
    it { is_expected.to validate_presence_of(:distance_method) }
    it { is_expected.to validate_presence_of(:results_limit) }
    it { is_expected.to validate_length_of(:custom_instructions).is_at_most(10_000) }
    it { is_expected.to validate_inclusion_of(:distance_method).in_array(Tools::RagSearchable::DISTANCE_METHODS) }

    it "validates connector is an SQL database" do
      other_connector = create(:connector, :llm_provider)
      rag_query = build(:tools_rag_query, connector: other_connector)
      expect(rag_query).not_to be_valid
      expect(rag_query.errors[:connector]).to include("must be an SQL Database connector")
    end

    it "allows SQL database connectors" do
      sql_connector = create(:connector, :sql_database)
      rag_query = build(:tools_rag_query, connector: sql_connector)
      expect(rag_query).to be_valid
    end

    it "validates llm_connector is an LLM Provider when set" do
      sql_connector = create(:connector, :sql_database)
      rq = build(:tools_rag_query, llm_connector: sql_connector, embedding_model_id: "embed-v1")
      expect(rq).not_to be_valid
      expect(rq.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end

    it "skips llm_connector validation when llm_connector_id is blank" do
      rq = build(:tools_rag_query, llm_connector: nil)
      expect(rq.errors[:llm_connector_id]).to be_empty
    end

    it "validates embedding_model_id presence when llm_connector is set" do
      llm = create(:connector, :llm_provider, :enabled)
      rq = build(:tools_rag_query, llm_connector: llm, embedding_model_id: nil)
      expect(rq).not_to be_valid
      expect(rq.errors[:embedding_model_id]).to include("can't be blank")
    end

    it "validates results_limit is positive integer" do
      rq = build(:tools_rag_query, results_limit: 0)
      expect(rq).not_to be_valid
    end

    it "validates results_limit does not exceed maximum" do
      rq = build(:tools_rag_query, results_limit: 101)
      expect(rq).not_to be_valid
    end

    it "validates max_distance range" do
      rq = build(:tools_rag_query, max_distance: 3.0)
      expect(rq).not_to be_valid
    end

    it "allows nil max_distance" do
      rq = build(:tools_rag_query, max_distance: nil)
      expect(rq).to be_valid
    end

    it "rejects SQL connectors outside the tool tenant" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      foreign_connector = create(:connector, :sql_database, tenant: create(:tenant))
      rq = create(:tool, :rag_query, operation:).configurator
      rq.connector_id = foreign_connector.id

      expect(rq).not_to be_valid
      expect(rq.errors[:connector]).to include("must be an SQL Database connector")
    end
  end

  describe "#distance_operator" do
    it "returns cosine operator for cosine" do
      rq = build(:tools_rag_query, distance_method: "cosine")
      expect(rq.distance_operator).to eq("<=>")
    end

    it "returns L2 operator for l2" do
      rq = build(:tools_rag_query, distance_method: "l2")
      expect(rq.distance_operator).to eq("<->")
    end

    it "returns inner product operator" do
      rq = build(:tools_rag_query, distance_method: "inner_product")
      expect(rq.distance_operator).to eq("<#>")
    end
  end

  describe "#selected_document_fields" do
    it "extracts field names from hash format" do
      rq = build(:tools_rag_query, document_fields: [{ "name" => "title" }, { "name" => "url" }])
      expect(rq.selected_document_fields).to eq(["title", "url"])
    end

    it "handles string format" do
      rq = build(:tools_rag_query, document_fields: ["title", "url"])
      expect(rq.selected_document_fields).to eq(["title", "url"])
    end

    it "returns empty array when nil" do
      rq = build(:tools_rag_query, document_fields: nil)
      rq.document_fields = nil
      expect(rq.selected_document_fields).to eq([])
    end
  end

  describe "#effective_instructions" do
    it "returns custom instructions when present" do
      rq = build(:tools_rag_query, custom_instructions: "Search my docs")
      expect(rq.effective_instructions).to eq("Search my docs")
    end

    it "returns default prompt when custom instructions are blank" do
      rq = build(:tools_rag_query, custom_instructions: nil)
      expect(rq.effective_instructions).to eq(Tools::RagSearchable::DEFAULT_TOOL_PROMPT)
    end
  end

  describe "#schema_discovered?" do
    it "returns true when schema and timestamp are present" do
      rq = build(:tools_rag_query, :with_schema)
      expect(rq.schema_discovered?).to be true
    end

    it "returns false when schema is empty" do
      rq = build(:tools_rag_query, discovered_schema: {}, schema_discovered_at: nil)
      expect(rq.schema_discovered?).to be false
    end
  end

  describe "#sql_database" do
    it "returns the connector" do
      rq = create(:tools_rag_query)
      expect(rq.sql_database).to eq(rq.connector)
    end

    it "returns nil when connector is nil" do
      rq = build(:tools_rag_query, connector: nil)
      expect(rq.sql_database).to be_nil
    end
  end

  describe "#all_discovered_table_names" do
    it "returns table names from discovered schema" do
      rq = build(:tools_rag_query, :with_schema)
      expect(rq.all_discovered_table_names).to include("chunks", "documents")
    end

    it "returns empty array when schema is nil" do
      rq = build(:tools_rag_query, discovered_schema: nil)
      expect(rq.all_discovered_table_names).to eq([])
    end

    it "returns empty array when objects key is missing" do
      rq = build(:tools_rag_query, discovered_schema: { "version" => 1 })
      expect(rq.all_discovered_table_names).to eq([])
    end
  end

  describe "#chunks_columns" do
    it "returns columns for the chunks table from discovered schema" do
      rq = build(:tools_rag_query, :with_schema)
      expect(rq.chunks_columns).to include("content", "embedding", "document_id")
    end

    it "returns empty array when no schema discovered" do
      rq = build(:tools_rag_query)
      expect(rq.chunks_columns).to eq([])
    end
  end

  describe "#documents_columns" do
    it "returns columns for the documents table from discovered schema" do
      rq = build(:tools_rag_query, :with_schema)
      expect(rq.documents_columns).to include("title", "url")
    end

    it "returns empty array when discovered_schema is nil" do
      rq = build(:tools_rag_query, discovered_schema: nil)
      expect(rq.documents_columns).to eq([])
    end
  end

  describe "#extract_table_columns edge cases" do
    it "returns empty array when table is not found in schema" do
      rq = build(:tools_rag_query, :with_schema, chunks_table: "nonexistent")
      expect(rq.chunks_columns).to eq([])
    end
  end

  describe "#llm_connector_must_be_llm_provider with stale connector" do
    it "adds an error when llm_connector_id is set but connector was deleted" do
      rq = build(:tools_rag_query,
                 llm_connector_id: 999_999_999,
                 embedding_model_id: "text-embedding-3-small",)
      allow(rq).to receive(:llm_connector).and_return(nil)
      rq.valid?
      expect(rq.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end
  end
end
