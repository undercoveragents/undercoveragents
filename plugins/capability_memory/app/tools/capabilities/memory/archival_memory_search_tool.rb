# frozen_string_literal: true

module Capabilities
  class Memory
    # Searches long-term archival memory by semantic similarity.
    # Results are ranked by relevance to the query, not by recency.
    class ArchivalMemorySearchTool < RubyLLM::Tool
      description "Search long-term archival memory using semantic similarity. " \
                  "Returns the most relevant stored memories for a given query. " \
                  "Use when you need to recall past facts, preferences, or events " \
                  "that may not be in the current context."

      param :query,
            desc: "Natural language search query. Finds semantically related memories " \
                  "even if exact words don't match.",
            type: :string

      param :tags,
            desc: "Optional tags to filter results (must match stored tags).",
            type: :array,
            required: false

      param :page,
            desc: "Page number for pagination, 0-indexed. Default 0.",
            type: :integer,
            required: false

      def self.for_agent(agent, user:, embedding_service:)
        new(agent, user, embedding_service:)
      end

      def initialize(agent, user, embedding_service:)
        super()
        @agent = agent
        @user  = user
        @embedding_service = embedding_service
      end

      def name
        "archival_memory_search"
      end

      def execute(query:, tags: [], page: 0)
        query_embedding = @embedding_service.embed(query)

        results = ArchivalMemory.semantic_search(
          agent_id: @agent.id,
          user_id: @user.id,
          query_embedding:,
          tags: Array(tags),
          page: page.to_i,
        )

        {
          results: format_results(results),
          page: page.to_i,
          count: results.length,
          query:,
        }
      rescue StandardError => e
        { success: false, error: "Archival memory search failed: #{e.message}" }
      end

      private

      def format_results(results)
        results.map do |m|
          {
            id: m.id,
            content: m.content,
            tags: m.tags,
            created_at: m.created_at.iso8601,
          }
        end
      end
    end
  end
end
