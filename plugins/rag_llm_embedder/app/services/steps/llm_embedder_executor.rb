# frozen_string_literal: true

module Rag
  module Steps
    class LlmEmbedderExecutor
      DEFAULT_MAX_INPUT_TOKENS = 8192

      def initialize(step_config, context = {})
        @config = step_config
        @context = context
      end

      def call(documents)
        normalized_documents = normalize_documents(documents)
        all_chunks = normalized_documents.flat_map(&:chunks)
        return normalized_documents if all_chunks.empty?

        embeddings = generate_embeddings(all_chunks)

        embedding_index = 0
        normalized_documents.map do |doc|
          updated_chunks = doc.chunks.map do |chunk|
            embedding = embeddings[embedding_index]
            embedding_index += 1
            chunk.with_embedding(embedding)
          end
          doc.with_chunks(updated_chunks)
        end
      end

      private

      def generate_embeddings(chunks)
        texts = chunks.map(&:content)
        embeddings = []
        llm_context = build_llm_context

        token_aware_batches(texts, @config.batch_size, max_batch_bytes).each do |batch|
          check_cancellation!
          embeddings.concat(embed_batch(batch, llm_context))
        end

        embeddings
      end

      def normalize_documents(documents)
        max_input_bytes = max_input_bytes_per_chunk

        documents.map do |doc|
          expanded_chunks = doc.chunks.flat_map do |chunk|
            split_chunk(chunk, max_input_bytes)
          end

          next doc if expanded_chunks == doc.chunks

          doc.with_chunks(resequence_chunks(expanded_chunks))
        end
      end

      def split_chunk(chunk, max_input_bytes)
        text = chunk.content.to_s
        return [chunk] if text.blank? || text.bytesize <= max_input_bytes

        split_text(text, max_input_bytes).map do |part|
          Rag::Chunk.new(
            content: part,
            position: chunk.position,
            metadata: chunk.metadata,
            embedding: chunk.embedding,
          )
        end
      end

      def split_text(text, max_input_bytes)
        parts = []
        current_part = +""
        current_bytes = 0

        text.each_char do |char|
          char_bytes = char.bytesize

          if current_bytes.positive? && (current_bytes + char_bytes > max_input_bytes)
            parts << current_part
            current_part = +""
            current_bytes = 0
          end

          if current_part.empty? && char_bytes > max_input_bytes
            parts << char
            next
          end

          current_part << char
          current_bytes += char_bytes
        end

        parts << current_part unless current_part.empty?
        parts
      end

      def resequence_chunks(chunks)
        chunks.each_with_index.map do |chunk, index|
          chunk.with(position: index)
        end
      end

      def embed_batch(batch, llm_context)
        response = if llm_context
                     RubyLLM.embed(batch, model: @config.model_id, context: llm_context)
                   else
                     RubyLLM.embed(batch, model: @config.model_id)
                   end

        if response.respond_to?(:vectors) then response.vectors
        elsif response.respond_to?(:embedding) then [response.embedding]
        else Array(response)
        end
      end

      def token_aware_batches(texts, max_items, max_bytes)
        batches = []
        current_batch = []
        current_bytes = 0

        texts.each do |text|
          text_bytes = text.to_s.bytesize

          if current_batch.size >= max_items || (current_batch.any? && current_bytes + text_bytes > max_bytes)
            batches << current_batch
            current_batch = []
            current_bytes = 0
          end

          current_batch << text
          current_bytes += text_bytes
        end

        batches << current_batch unless current_batch.empty?
        batches
      end

      def check_cancellation!
        return unless @context[:run_id]

        run = RagRun.select(:status).find(@context[:run_id])
        raise Rag::PipelineExecutor::CancelledError, "Run was cancelled" if run.cancelled?
      end

      def build_llm_context
        llm_provider = llm_connector
        return nil unless llm_provider.respond_to?(:build_context)

        llm_provider.build_context
      end

      def llm_connector
        return @config.llm_connector if @config.respond_to?(:llm_connector)

        nil
      end

      def max_batch_bytes
        @config.max_tokens_per_batch
      end

      def max_input_bytes_per_chunk
        [resolved_model_context_window, @config.max_tokens_per_batch, DEFAULT_MAX_INPUT_TOKENS].compact.min
      end

      def resolved_model_context_window
        provider = llm_connector&.provider
        return nil if provider.blank? || @config.model_id.blank?

        Model.find_by(provider:, model_id: @config.model_id)&.context_window
      end
    end
  end
end
