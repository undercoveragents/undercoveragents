# frozen_string_literal: true

module ChatReferences
  class SelectionResolver
    SCOPE_BUILDERS = {
      "operation" => :scope_for_operation,
      "operation_via_skill_catalog" => :scope_for_skill_catalog_operation,
      "tenant" => :scope_for_tenant,
      "tenant_via_test_target" => :scope_for_test_target_tenant,
    }.freeze

    def initialize(tenant:, operation:, kinds:)
      @tenant = tenant
      @operation = operation
      @definitions = Registry.fetch_many(kinds).index_by(&:kind)
    end

    def resolve(payload)
      parse(payload).filter_map { |raw_reference| resolve_one(raw_reference) }.uniq do |reference|
        [reference["kind"], reference["id"], reference["mention"]]
      end
    end

    private

    attr_reader :tenant, :operation, :definitions

    def parse(payload)
      value = payload.is_a?(String) ? JSON.parse(payload.presence || "[]") : payload
      Array(value).grep(Hash)
    rescue JSON::ParserError
      []
    end

    def resolve_one(raw_reference)
      raw_reference = raw_reference.stringify_keys
      definition = definitions[raw_reference["kind"].to_s]
      return unless definition

      record = scoped_record(definition, raw_reference)
      return unless record

      serialize(record, definition, raw_reference)
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

    def serialize(record, definition, raw_reference)
      mention = sanitized_mention(raw_reference["mention"])
      {
        "kind" => definition.kind,
        "type" => definition.type_label,
        "id" => record.id,
        "slug" => record.try(:slug).presence,
        "label" => definition.record_label(record),
        "mention" => mention,
      }.compact
    end

    def sanitized_mention(value)
      mention = value.to_s.strip
      return if mention.blank?
      return unless mention.match?(/\A#[\w:-]{1,80}\z/)

      mention
    end

    def scoped_record(definition, raw_reference)
      if raw_reference["sgid"].present?
        signed_record = record_from_signed_id(raw_reference["sgid"], definition)
        return unless signed_record

        return scoped_records(definition).find_by(id: signed_record.id)
      end

      scoped_records(definition).find_by(id: raw_reference["id"])
    end

    def record_from_signed_id(sgid, definition)
      record = GlobalID::Locator.locate_signed(sgid, for: SIGNED_ID_PURPOSE)
      return unless record.is_a?(definition.model_class)

      record
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def tenant_scoped_test_suites(scope)
      scope.where(agent_id: tenant.agents.select(:id))
           .or(scope.where(mission_id: tenant.missions.select(:id)))
    end
  end
end
