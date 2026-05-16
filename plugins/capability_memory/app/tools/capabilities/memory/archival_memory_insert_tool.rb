# frozen_string_literal: true

module Capabilities
  class Memory
    # Stores information in long-term archival memory for later semantic retrieval.
    # Unlike memory blocks, archival memories are NOT always in context — they must
    # be explicitly searched with archival_memory_search.
    class ArchivalMemoryInsertTool < RubyLLM::Tool
      description "Store information in long-term archival memory. " \
                  "Use for facts, summaries, or events useful to remember long-term " \
                  "but that don't need to be visible in every response. " \
                  "Retrieve later with archival_memory_search."

      param :content,
            desc: "The information to store. Be specific and self-contained — " \
                  "this entry will be retrieved without surrounding context.",
            type: :string

      param :tags,
            desc: "Optional list of tags for categorization (e.g. ['preferences', 'rails']). " \
                  "Used to filter search results.",
            type: :array,
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
        "archival_memory_insert"
      end

      def execute(content:, tags: [])
        embedding = @embedding_service.embed(content)

        memory = @agent.archival_memories.create!(
          user: @user,
          content:,
          embedding:,
          tags: Array(tags),
        )

        {
          success: true,
          id: memory.id,
          content_preview: content.truncate(100),
          tags: memory.tags,
        }
      rescue StandardError => e
        { success: false, error: "Failed to store archival memory: #{e.message}" }
      end
    end
  end
end
