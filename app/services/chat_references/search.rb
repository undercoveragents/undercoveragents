# frozen_string_literal: true

module ChatReferences
  class Search
    LIMIT_PER_KIND = 8
    SCOPE_BUILDERS = {
      "operation" => :scope_for_operation,
      "operation_via_skill_catalog" => :scope_for_skill_catalog_operation,
      "tenant" => :scope_for_tenant,
      "tenant_via_test_target" => :scope_for_test_target_tenant,
    }.freeze

    def initialize(tenant:, operation:, kinds:)
      @tenant = tenant
      @operation = operation
      @definitions = Registry.fetch_many(kinds)
    end

    def call(query: nil)
      definitions.filter_map do |definition|
        items = records_for(definition, query:).limit(LIMIT_PER_KIND).map do |record|
          serialize(record, definition)
        end
        next if items.empty?

        { kind: definition.kind, label: definition.label, icon: definition.icon, items: }
      end
    end

    private

    attr_reader :tenant, :operation, :definitions

    def records_for(definition, query:)
      scope = scoped_records(definition)
      scope = apply_query(scope, definition, query.to_s.strip) if query.present?
      ordered(scope)
    end

    def scoped_records(definition)
      scope = definition.model_class.all

      apply_scope(scope, definition.scope)
    end

    def apply_scope(scope, scope_name)
      builder = SCOPE_BUILDERS[scope_name]
      builder ? send(builder, scope) : scope.none
    end

    def scope_for_operation(scope)
      operation ? scope.where(operation:) : scope.none
    end

    def scope_for_skill_catalog_operation(scope)
      return scope.none unless operation

      scope.joins(:skill_catalog).where(skill_catalogs: { operation_id: operation.id })
    end

    def scope_for_tenant(scope)
      tenant ? scope.where(tenant:) : scope.none
    end

    def scope_for_test_target_tenant(scope)
      tenant ? tenant_scoped_test_suites(scope) : scope.none
    end

    def apply_query(scope, definition, query)
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
      table = definition.model_class.arel_table
      predicates = definition.search_columns.map do |column_name|
        Arel::Nodes::NamedFunction.new("LOWER", [table[column_name]]).matches(pattern)
      end

      scope.where(predicates.reduce { |memo, predicate| memo.or(predicate) })
    end

    def ordered(scope)
      return scope.ordered if scope.respond_to?(:ordered)

      scope.order(:name)
    end

    def serialize(record, definition)
      {
        id: record.id,
        sgid: definition.signed_id_for(record),
        kind: definition.kind,
        type: definition.type_label,
        label: definition.record_label(record),
        subtitle: record_subtitle(record),
        icon: record_icon(record, definition),
        mention: definition.mention_for(record),
        display_mention: definition.mention_for(record),
        display_tag: definition.display_tag(record),
      }.compact
    end

    def record_subtitle(record)
      skill_subtitle(record) ||
        connector_subtitle(record) ||
        test_suite_subtitle(record) ||
        type_label_subtitle(record) ||
        description_subtitle(record)
    end

    def skill_subtitle(record)
      record.skill_catalog.name if record.is_a?(Skill)
    end

    def connector_subtitle(record)
      record.connector_type.to_s.titleize if record.is_a?(Connector)
    end

    def test_suite_subtitle(record)
      return unless record.is_a?(TestSuite)

      record.agent&.name || record.mission&.name || record.suite_type.to_s.titleize
    end

    def type_label_subtitle(record)
      record.type_label if record.respond_to?(:type_label)
    end

    def description_subtitle(record)
      record.try(:description).to_s.truncate(80).presence
    end

    def record_icon(record, definition)
      return record.type_icon if record.respond_to?(:type_icon)

      definition.icon
    end

    def tenant_scoped_test_suites(scope)
      scope.where(agent_id: tenant.agents.select(:id))
           .or(scope.where(mission_id: tenant.missions.select(:id)))
    end
  end
end
