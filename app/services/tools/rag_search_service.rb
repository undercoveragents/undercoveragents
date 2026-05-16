# frozen_string_literal: true

module Tools
  # Generic RAG search service that works with any RagSearchable model.
  #
  # Performs vector similarity search against a PostgreSQL+pgvector database.
  # Configuration (tables, fields, distance method, limits) comes from
  # the searchable model — which can be a Tools::RagQuery or Tools::RagFlow.
  #
  # Steps:
  # 1. Embeds the user query using the configured embedding model via RubyLLM
  # 2. Runs a nearest-neighbor search against the chunks table
  # 3. Joins with the documents table to fetch metadata
  # 4. Returns formatted results with document fields and distance scores
  #
  # Safety:
  # - Executes inside a READ-ONLY transaction that is always rolled back
  # - Uses parameterized identifiers to prevent SQL injection
  #
  # Usage:
  #   service = Tools::RagSearchService.new(searchable, llm_context: context)
  #   results = service.search("machine learning concepts", limit: 10)
  #   # => [{ chunk_content: "...", distance: 0.1234, title: "...", ... }]
  #
  class RagSearchService
    include ConnectionConfigBuilder

    # @param searchable [Tools::RagQuery, Tools::RagFlow] any RagSearchable model
    # @param llm_context [Object, nil] optional LLM provider context
    def initialize(searchable, llm_context: nil)
      @searchable = searchable
      @llm_context = llm_context
    end

    # @param query [String] natural language search query
    # @param limit [Integer] max number of chunks to return
    # @return [Array<Hash>] matched chunks with document metadata and distances
    def search(query, limit: nil)
      effective_limit = limit || @searchable.results_limit
      embedding = generate_embedding(query)
      execute_search(embedding, effective_limit)
    end

    private

    # ── Embedding Generation ──────────────────────────────────────

    def generate_embedding(query)
      embedding_response = RubyLLM.embed(query, model: embedding_model, context: @llm_context)
      embedding_response.vectors
    end

    def embedding_model
      @searchable.embedding_model_id || raise("No embedding model configured for RAG tool")
    end

    # ── Search Execution ──────────────────────────────────────────

    def execute_search(embedding, limit)
      sql = build_search_sql(embedding, limit)
      rows = execute_read_only(sql)
      format_results(rows)
    end

    def build_search_sql(embedding, limit)
      ids = table_identifiers
      embedding_literal = format_pg_vector(embedding)
      distance_expr = "#{ids[:chunks]}.#{ids[:embedding_col]} #{ids[:operator]} '#{embedding_literal}'"
      select_fields = build_select_fields(ids[:chunks], ids[:documents], ids[:content_col])

      sql = "SELECT #{select_fields}, #{distance_expr} AS distance"
      sql << " FROM #{ids[:chunks]}"
      sql << " JOIN #{ids[:documents]} ON #{ids[:chunks]}.#{ids[:doc_ref]} = #{ids[:documents]}.id"
      sql << " WHERE #{distance_expr} <= #{@searchable.max_distance}" if @searchable.max_distance.present?
      sql << " ORDER BY distance ASC LIMIT #{limit.to_i}"
    end

    def table_identifiers
      {
        operator: @searchable.distance_operator,
        chunks: sanitize_identifier(@searchable.chunks_table),
        documents: sanitize_identifier(@searchable.documents_table),
        embedding_col: sanitize_identifier(@searchable.embedding_field),
        content_col: sanitize_identifier(@searchable.chunk_content_field),
        doc_ref: sanitize_identifier(@searchable.document_reference_field),
      }
    end

    def build_select_fields(chunks, documents, content_col)
      fields = ["#{chunks}.#{content_col} AS chunk_content"]

      @searchable.selected_document_fields.each do |field|
        safe_field = sanitize_identifier(field)
        fields << "#{documents}.#{safe_field} AS #{safe_field}"
      end

      fields.join(", ")
    end

    # ── Database Execution ────────────────────────────────────────

    # :nocov:
    def execute_read_only(sql)
      with_pg_connection do |conn|
        conn.exec("BEGIN")
        conn.exec("SET TRANSACTION READ ONLY")
        result = conn.exec(sql)
        rows = result.to_a
        conn.exec("ROLLBACK")
        rows
      rescue StandardError => e
        rollback_transaction(conn)
        raise e
      end
    end

    def rollback_transaction(conn)
      conn.exec("ROLLBACK")
    rescue StandardError
      nil
    end

    def with_pg_connection
      require "pg"
      conn = connect_pg(build_pg_config_for(@searchable.sql_database))
      begin
        yield conn
      ensure
        conn.close
      end
    end
    # :nocov:

    # ── Formatting ────────────────────────────────────────────────

    def format_results(rows)
      rows.map do |row|
        result = { chunk_content: row["chunk_content"], distance: row["distance"]&.to_f&.round(4) }

        @searchable.selected_document_fields.each do |field|
          result[field.to_sym] = row[field]
        end

        result
      end
    end

    def format_pg_vector(embedding)
      "[#{embedding.join(",")}]"
    end

    def sanitize_identifier(name)
      # Only allow alphanumeric, underscores, and dots (for schema.table)
      raise ArgumentError, "Invalid identifier: #{name}" unless name.match?(/\A[a-zA-Z_][a-zA-Z0-9_.]*\z/)

      name
    end
  end
end
