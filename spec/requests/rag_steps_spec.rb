# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rag::Steps" do
  let(:flow) { create(:rag_flow) }

  def stub_sql_source_query_validation(connector, columns: ["body"])
    inspector = instance_double(Rag::SqlDatabaseSourceInspector)
    allow(Rag::SqlDatabaseSourceInspector).to receive(:new).with(connector).and_return(inspector)
    allow(inspector).to receive(:validate_query).and_return(
      Rag::SqlDatabaseSourceInspector::Result.new(
        success?: true,
        message: "Query is valid!",
        objects: [],
        columns:,
      ),
    )
  end

  def stub_sql_source_schema_options(connector, object_name:, columns:, object_type: "table")
    inspector = instance_double(Rag::SqlDatabaseSourceInspector)
    allow(Rag::SqlDatabaseSourceInspector).to receive(:new).with(connector).and_return(inspector)
    allow(inspector).to receive(:schema_options).and_return(
      Rag::SqlDatabaseSourceInspector::Result.new(
        success?: true,
        message: "Discovered 1 object",
        objects: [{
          "name" => object_name,
          "type" => object_type,
          "columns" => columns.map { |column| { "name" => column } },
        }],
        columns: [],
      ),
    )
  end

  def sql_source_table_params(connector)
    {
      connector_id: connector.id,
      source_mode: "table",
      selected_object_name: "kb_documents",
      selected_object_type: "table",
      content_column: "plain_text",
      metadata_columns: ["title", "description"],
      incremental_column: "updated_at",
      batch_size: 500,
      record_limit: 100,
    }
  end

  def expected_sql_source_table_configuration(connector)
    {
      "connector_id" => connector.id,
      "source_mode" => "table",
      "selected_object_name" => "kb_documents",
      "selected_object_type" => "table",
      "content_column" => "plain_text",
      "metadata_columns" => ["title", "description"],
      "incremental_column" => "updated_at",
      "batch_size" => 500,
      "record_limit" => 100,
      "query" => 'SELECT "plain_text", "title", "description", "updated_at" FROM "public"."kb_documents" LIMIT 100',
    }
  end

  def source_configuration(query:, connector_id: nil)
    {
      "connector_id" => connector_id,
      "source_mode" => "query",
      "query" => query,
      "content_column" => "body",
      "metadata_columns" => [],
      "batch_size" => 1000,
    }.compact
  end

  def storage_configuration(documents_table:)
    {
      "connector_id" => nil,
      "storage_mode" => "new",
      "documents_table" => documents_table,
      "chunks_table" => "persisted_chunks",
      "content_field" => "content",
      "embedding_field" => "embedding",
      "document_reference_field" => "document_id",
      "pre_load_action" => "none",
      "upsert_enabled" => false,
      "auto_create_tables" => true,
      "embedding_dimensions" => 1536,
      "metadata_column_types" => {},
      "metadata_field_mappings" => {},
    }
  end

  def create_source_step(query:, connector: nil)
    create(
      :rag_step,
      rag_flow: flow,
      stage: "source",
      module_type: "sql_database_source",
      configuration: source_configuration(query:, connector_id: connector&.id),
    )
  end

  def create_storage_step(documents_table:)
    create(
      :rag_step,
      rag_flow: flow,
      stage: "storage",
      module_type: "sql_database_storage",
      configuration: storage_configuration(documents_table:),
    )
  end

  def preview_source_params(connector)
    {
      module_type: "sql_database_source",
      sql_database_source: {
        connector_id: connector.id,
        source_mode: "query",
        query: "SELECT body FROM preview_docs",
        content_column: "body",
      },
    }
  end

  def preview_storage_params
    {
      module_type: "sql_database_storage",
      sql_database_storage: {
        storage_mode: "new",
        documents_table: "preview_documents",
        chunks_table: "preview_chunks",
        content_field: "content",
        embedding_field: "embedding",
        document_reference_field: "document_id",
        pre_load_action: "none",
        embedding_dimensions: 1536,
      },
    }
  end

  describe "GET /...steps/:stage/edit" do
    it "returns a successful response for an unconfigured stage" do
      get edit_admin_rag_flow_step_path(flow, "chunking")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Chunking")
    end

    it "returns a successful response for a configured stage" do
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)
      get edit_admin_rag_flow_step_path(flow, "chunking")
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown stage" do
      get edit_admin_rag_flow_step_path(flow, "unknown")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown module_type" do
      get edit_admin_rag_flow_step_path(
        flow,
        "chunking",
        module_type: "totally_unknown_module_xyz",
      )
      expect(response).to have_http_status(:not_found)
    end

    it "renders fixed_size_chunker fields with scoped builder names" do
      get edit_admin_rag_flow_step_path(
        flow,
        "chunking",
        module_type: "fixed_size_chunker",
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="fixed_size_chunker[chunk_size]"')
      expect(response.body).to include('name="fixed_size_chunker[chunk_overlap]"')
      expect(response.body).to include('name="fixed_size_chunker[separator]"')
    end

    it "renders paragraph_chunker fields with scoped builder names" do
      get edit_admin_rag_flow_step_path(
        flow,
        "chunking",
        module_type: "paragraph_chunker",
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="paragraph_chunker[chunk_size]"')
      expect(response.body).to include('name="paragraph_chunker[chunk_overlap]"')
      expect(response.body).to include('name="paragraph_chunker[min_paragraph_size]"')
    end

    it "renders sentence_chunker fields with scoped builder names" do
      get edit_admin_rag_flow_step_path(
        flow,
        "chunking",
        module_type: "sentence_chunker",
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="sentence_chunker[chunk_size]"')
      expect(response.body).to include('name="sentence_chunker[chunk_overlap]"')
    end

    it "renders markdown_chunker fields with scoped builder names" do
      get edit_admin_rag_flow_step_path(
        flow,
        "chunking",
        module_type: "markdown_chunker",
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="markdown_chunker[chunk_size]"')
      expect(response.body).to include('name="markdown_chunker[chunk_overlap]"')
    end

    it "renders sql_database_source fields with scoped builder names" do
      create(:connector, :sql_database, :enabled)

      get edit_admin_rag_flow_step_path(
        flow,
        "source",
        module_type: "sql_database_source",
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="sql_database_source[connector_id]"')
      expect(response.body).to include('name="sql_database_source[query]"')
      expect(response.body).to include('name="sql_database_source[content_column]"')
      expect(response.body).to include('data-turbo-frame="app-content-frame"')
    end

    it "renders llm_embedder fields with scoped builder names" do
      create(:connector, :llm_provider, :enabled)

      get edit_admin_rag_flow_step_path(
        flow,
        "embedding",
        module_type: "llm_embedder",
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="llm_embedder[llm_connector_id]"')
      expect(response.body).to include('name="llm_embedder[model_id]"')
      expect(response.body).to include('name="llm_embedder[batch_size]"')
    end

    it "renders sql_database_storage fields with scoped builder names" do # rubocop:disable RSpec/MultipleExpectations
      create(:connector, :sql_database, :enabled)

      get edit_admin_rag_flow_step_path(
        flow,
        "storage",
        module_type: "sql_database_storage",
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="sql_database_storage[connector_id]"')
      expect(response.body).to include('name="sql_database_storage[storage_mode]"')
      expect(response.body).to include('name="sql_database_storage[documents_table]"')
      expect(response.body).to include('name="sql_database_storage[auto_create_tables]"')
      expect(response.body).to include('value="delete_matching"')
      expect(response.body).not_to include('value="drop_and_create"')
    end

    it "uses preview params for modules without build_from_params" do
      create(
        :rag_step,
        rag_flow: flow,
        stage: "chunking",
        module_type: "fixed_size_chunker",
        configuration: { "chunk_size" => 1000, "chunk_overlap" => 200, "separator" => "\n\n" },
      )

      get edit_admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "fixed_size_chunker",
        fixed_size_chunker: { chunk_size: 321, chunk_overlap: 24, separator: "---" },
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="321"')
      expect(response.body).not_to include('value="1000"')
    end

    it "uses SQL source preview params instead of persisted step configuration" do
      persisted_connector = create(:connector, :sql_database, :enabled)
      preview_connector = create(:connector, :sql_database, :enabled)
      create_source_step(query: "SELECT body FROM persisted_docs", connector: persisted_connector)
      stub_sql_source_query_validation(preview_connector)

      get edit_admin_rag_flow_step_path(flow, "source"), params: preview_source_params(preview_connector)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SELECT body FROM preview_docs")
      expect(response.body).not_to include("SELECT body FROM persisted_docs")
    end

    it "uses SQL storage preview params instead of persisted step configuration" do
      create(:connector, :sql_database, :enabled)
      create_storage_step(documents_table: "persisted_documents")

      get edit_admin_rag_flow_step_path(flow, "storage"), params: preview_storage_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="preview_documents"')
      expect(response.body).not_to include('value="persisted_documents"')
      expect(response.body).to include("preview_documents: id, content_hash, created_at.")
      expect(response.body).not_to include("%code")
    end
  end

  describe "PATCH /...steps/:stage" do
    it "creates a new step when none exists" do
      expect do
        patch admin_rag_flow_step_path(flow, "chunking"), params: {
          module_type: "fixed_size_chunker",
          fixed_size_chunker: { chunk_size: 1000, chunk_overlap: 200 },
        }
      end.to change(RagStep, :count).by(1)

      expect(response).to redirect_to(admin_rag_flow_path(flow))
      step = flow.reload.step_for(:chunking)
      expect(step.module_type).to eq("fixed_size_chunker")
      expect(step.configuration["chunk_size"]).to eq(1000)
    end

    it "updates an existing step with the same module type" do
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 500, "chunk_overlap" => 50 },)

      patch admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "fixed_size_chunker",
        fixed_size_chunker: { chunk_size: 800, chunk_overlap: 100 },
      }

      step = flow.reload.step_for(:chunking)
      expect(step.configuration["chunk_size"]).to eq(800)
      expect(step.configuration["chunk_overlap"]).to eq(100)
    end

    it "replaces the module when switching types" do
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)

      patch admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "paragraph_chunker",
        paragraph_chunker: { chunk_size: 1000, chunk_overlap: 200, min_paragraph_size: 50 },
      }

      flow.reload
      step = flow.step_for(:chunking)
      expect(step.module_type).to eq("paragraph_chunker")
      expect(step.configurator).to be_a(RagSteps::ParagraphChunker)
    end

    it "creates a SQL database source step" do
      connector = create(:connector, :sql_database, :enabled)
      stub_sql_source_query_validation(connector)

      expect do
        patch admin_rag_flow_step_path(flow, "source"), params: {
          module_type: "sql_database_source",
          sql_database_source: {
            connector_id: connector.id,
            source_mode: "query",
            query: "SELECT body FROM t",
            content_column: "body",
          },
        }
      end.to change(RagStep, :count).by(1)

      step = flow.reload.step_for(:source)
      expect(step.module_type).to eq("sql_database_source")
    end

    it "persists every SQL source wizard field" do
      connector = create(:connector, :sql_database, :enabled)
      stub_sql_source_schema_options(
        connector,
        object_name: "kb_documents",
        columns: ["plain_text", "title", "description", "updated_at"],
      )

      patch admin_rag_flow_step_path(flow, "source"), params: {
        module_type: "sql_database_source",
        sql_database_source: sql_source_table_params(connector),
      }

      expect(response).to redirect_to(admin_rag_flow_path(flow))
      expect(flow.reload.step_for(:source).configuration).to include(expected_sql_source_table_configuration(connector))
    end

    it "redirects to flow show on success" do
      patch admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "fixed_size_chunker",
        fixed_size_chunker: { chunk_size: 1000, chunk_overlap: 200 },
      }
      expect(response).to redirect_to(admin_rag_flow_path(flow))
    end

    it "rejects modules that don't belong to the stage" do
      patch admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "sql_database_source",
        sql_database_source: { query: "SELECT 1", content_column: "c" },
      }
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a completely unknown module_type" do
      patch admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "totally_unknown_module_xyz",
      }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /...steps/:stage" do
    it "removes the step configuration" do
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)

      expect do
        delete admin_rag_flow_step_path(flow, "chunking")
      end.to change(RagStep, :count).by(-1)

      expect(response).to redirect_to(
        edit_admin_rag_flow_step_path(flow, "chunking"),
      )
    end

    it "does nothing gracefully when no step is configured" do
      delete admin_rag_flow_step_path(flow, "chunking")
      expect(response).to redirect_to(
        edit_admin_rag_flow_step_path(flow, "chunking"),
      )
    end
  end

  describe "PATCH /...steps/:stage with validation errors" do
    it "re-renders edit with unprocessable_content status when update fails" do
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 500, "chunk_overlap" => 50 },)

      patch admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "fixed_size_chunker",
        fixed_size_chunker: { chunk_size: 0, chunk_overlap: 100 },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "re-renders edit when creating a new step with invalid params" do
      patch admin_rag_flow_step_path(flow, "chunking"), params: {
        module_type: "fixed_size_chunker",
        fixed_size_chunker: { chunk_size: 0, chunk_overlap: 100 },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
