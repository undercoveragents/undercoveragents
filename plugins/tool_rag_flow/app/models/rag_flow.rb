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
module Tools
  class RagFlow
    include UndercoverAgents::PluginSystem::Configurator
    include ToolWidgetConfigurable
    include ToolPlugin
    include Tools::RagSearchable

    attr_accessor :_tool_record

    attribute :rag_flow_id, :integer
    attribute :custom_instructions, :string
    attribute :distance_method, :string, default: "cosine"
    attribute :document_fields, default: -> { [] }
    attribute :max_distance, :float, default: 0.8
    attribute :results_limit, :integer, default: 10

    validate :rag_flow_must_have_storage_step
    validate :rag_flow_must_have_embedding_step

    # ── Tool Type Protocol ────────────────────────────────────────

    def self.type_key = "rag_flow"
    def self.type_label = "RAG"
    def self.type_icon = "fa-solid fa-diagram-project"

    def self.tool_widget_default_presentation(display_name:, icon:)
      ToolCalls::Presentation.new(
        display_name:,
        icon:,
        running_messages: [
          "Searching the RAG flow…",
          "Tracing vector matches…",
          "Hydrating flow-backed context…",
        ],
        complete_messages: [
          "RAG flow results prepared.",
          "Flow-backed context assembled.",
          "Relevant documents are ready.",
        ],
      )
    end

    def self.tool_designer_editable_attributes
      [
        "rag_flow_id",
        "custom_instructions",
        "distance_method",
        "max_distance",
        "results_limit",
        *ToolWidgetConfigurable::DESIGNER_ATTRIBUTE_KEYS,
      ]
    end

    def self.tool_designer_notes
      [
        "Use list_resources(kind: \"rag_flows\") to resolve rag_flow_id values.",
        "The referenced RAG flow must already have a SQL storage step and an LLM embedding step configured.",
      ]
    end

    def self.tool_designer_field_hints = { "rag_flow_id" => resource_hint("rag_flows") }

    def self.tool_designer_resource_kinds
      [tool_designer_resource_kind(kind: "rag_flows", title: "RAG Flows", model_name: "RagFlow",
                                   scope: "operation_owned",)]
    end

    def self.runtime_tool_adapter_class_name = "RagFlowTool"

    def self.permitted_params(params)
      permit_params_with_widget(
        params,
        [:rag_flow_id, :custom_instructions, :distance_method,
         :max_distance, :results_limit,],
      )
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def save!
      update_rag_flow_id_from_cache
      super
    end

    def reset_configurator_caches
      @rag_flow_cache = nil
    end

    # ── RagFlow accessor ──────────────────────────────────────────

    def rag_flow
      # :nocov:
      return @rag_flow_cache if defined?(@rag_flow_cache) && @rag_flow_cache&.id == rag_flow_id
      # :nocov:
      return nil if rag_flow_id.blank?

      @rag_flow_cache = ::RagFlow.find_by(id: rag_flow_id)
    end

    def rag_flow=(flow)
      @rag_flow_cache = flow
      self.rag_flow_id = flow&.id
    end

    # ── RagSearchable interface (delegated to rag flow steps) ──

    def sql_database
      storage_step&.connector
    end

    def chunks_table
      storage_step&.chunks_table
    end

    def documents_table
      storage_step&.documents_table
    end

    def embedding_field
      storage_step&.embedding_field
    end

    def chunk_content_field
      storage_step&.content_field
    end

    def document_reference_field
      storage_step&.document_reference_field
    end

    def embedding_model_id
      embedding_step&.model_id
    end

    def llm_connector
      embedding_step&.llm_connector
    end

    # Returns all document metadata fields available in the documents table.
    # Overrides RagSearchable#selected_document_fields — auto-derived, no manual selection.
    #
    # When the storage step has explicit metadata_field_mappings (e.g. { "src_col" => "db_col" }),
    # returns the VALUES — the actual destination column names in the documents table.
    #
    # When metadata_field_mappings is empty (auto-mapping mode), the storage executor
    # maps source metadata_columns to identically-named DB columns, so we fall back
    # to the source step’s metadata_columns list.
    def selected_document_fields
      storage = storage_step
      return [] unless storage

      mappings = storage.metadata_field_mappings
      if mappings.present?
        mappings.values.uniq
      else
        source = rag_flow.module_for(:source)
        Array(source.try(:metadata_columns))
      end
    end

    # ── Convenience accessors ─────────────────────────────────────

    def storage_step
      rag_flow&.module_for(:storage)
    end

    def embedding_step
      rag_flow&.module_for(:embedding)
    end

    private

    # :nocov:
    def update_rag_flow_id_from_cache
      self.rag_flow_id = @rag_flow_cache&.id if defined?(@rag_flow_cache)
    end
    # :nocov:

    def rag_flow_must_have_storage_step
      return if rag_flow.blank?

      step = rag_flow.step_for(:storage)
      return if step&.module_type == "sql_database_storage"

      errors.add(:rag_flow, "must have a SQL Database Storage step configured")
    end

    def rag_flow_must_have_embedding_step
      return if rag_flow.blank?

      step = rag_flow.step_for(:embedding)
      return if step&.module_type == "llm_embedder"

      errors.add(:rag_flow, "must have an LLM Embedder step configured")
    end
  end
end
