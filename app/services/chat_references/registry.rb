# frozen_string_literal: true

module ChatReferences
  SIGNED_ID_PURPOSE = "chat_reference"

  Definition = Data.define(:kind, :label, :model_name, :scope, :icon, :search_columns) do
    def model_class = model_name.constantize

    def type_label = label.to_s.singularize

    def mention_base = "##{type_label.parameterize}"

    def record_label(record)
      record.try(:name).presence || "#{record.class.model_name.human} ##{record.id}"
    end

    def mention_for(record)
      slug = record_label(record).parameterize
      return "##{slug}" if slug.present?

      "#{mention_base}-#{record.id}"
    end

    def display_tag(record)
      "##{type_label.parameterize(separator: "_")}_id:#{record.id}"
    end

    def signed_id_for(record)
      record.to_sgid(for: SIGNED_ID_PURPOSE).to_s
    end
  end

  class Registry
    DEFAULT_DEFINITIONS = [
      Definition.new(
        kind: "missions",
        label: "Missions",
        model_name: "Mission",
        scope: "operation",
        icon: "fa-solid fa-diagram-project",
        search_columns: ["name", "description"],
      ),
      Definition.new(
        kind: "tools",
        label: "Tools",
        model_name: "Tool",
        scope: "operation",
        icon: "fa-solid fa-wrench",
        search_columns: ["name", "description"],
      ),
      Definition.new(
        kind: "skill_catalogs",
        label: "Skill Catalogs",
        model_name: "SkillCatalog",
        scope: "operation",
        icon: "fa-solid fa-book-open",
        search_columns: ["name", "description"],
      ),
      Definition.new(
        kind: "skills",
        label: "Skills",
        model_name: "Skill",
        scope: "operation_via_skill_catalog",
        icon: "fa-solid fa-wand-magic-sparkles",
        search_columns: ["name", "description"],
      ),
      Definition.new(
        kind: "agents",
        label: "Agents",
        model_name: "Agent",
        scope: "operation",
        icon: "fa-solid fa-robot",
        search_columns: ["name"],
      ),
      Definition.new(
        kind: "clients",
        label: "Clients",
        model_name: "Client",
        scope: "tenant",
        icon: "fa-solid fa-palette",
        search_columns: ["name"],
      ),
      Definition.new(
        kind: "connectors",
        label: "Connectors",
        model_name: "Connector",
        scope: "tenant",
        icon: "fa-solid fa-plug",
        search_columns: ["name", "description"],
      ),
      Definition.new(
        kind: "rag_flows",
        label: "RAG Flows",
        model_name: "RagFlow",
        scope: "operation",
        icon: "fa-solid fa-layer-group",
        search_columns: ["name"],
      ),
      Definition.new(
        kind: "test_suites",
        label: "Test Suites",
        model_name: "TestSuite",
        scope: "tenant_via_test_target",
        icon: "fa-solid fa-vial-circle-check",
        search_columns: ["name", "description"],
      ),
    ].freeze

    class << self
      def register(definition)
        definitions[definition.kind] = definition
      end

      def fetch_many(kinds)
        Array(kinds).filter_map { |kind| definitions[kind.to_s] }
      end

      def definitions
        @definitions ||= DEFAULT_DEFINITIONS.index_by(&:kind)
      end
    end
  end
end
