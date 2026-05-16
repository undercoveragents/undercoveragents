# frozen_string_literal: true

module MissionDesigner
  class TargetMissionResolver
    def initialize(fallback_mission:, runtime_context: nil)
      @fallback_mission = fallback_mission
      @runtime_context = runtime_context
    end

    def resolve(mission_id = nil)
      identifier = mission_id.to_s.strip
      return resolve_blank_identifier if identifier.blank?

      fallback_match = fallback_mission_match(identifier)
      return fallback_match if fallback_match

      scope = mission_scope
      scope.find_by(id: identifier) ||
        scope.find_by(slug: identifier) ||
        unique_name_match(scope, identifier) ||
        raise(ActiveRecord::RecordNotFound, "Mission '#{identifier}' was not found.")
    end

    def unique_name_match(scope, identifier)
      matches = scope.where("LOWER(missions.name) = ?", identifier.downcase).limit(2).to_a
      return matches.first if matches.one?
      return nil if matches.empty?

      raise ActiveRecord::RecordNotFound,
            "Multiple missions named '#{identifier}' were found. Pass the numeric ID or slug instead."
    end

    private

    def resolve_blank_identifier
      return @fallback_mission if @fallback_mission.present?

      raise ArgumentError, "No mission is available. Provide mission_id or open a mission page first."
    end

    def fallback_mission_match(identifier)
      return if @fallback_mission.blank?

      return @fallback_mission if identifier.casecmp(@fallback_mission.id.to_s).zero?
      return @fallback_mission if identifier.casecmp(@fallback_mission.slug.to_s).zero?
      return @fallback_mission if identifier.casecmp(@fallback_mission.name.to_s).zero?
      return @fallback_mission if fallback_name_tokens.include?(identifier.downcase)

      nil
    end

    def fallback_name_tokens
      @fallback_name_tokens ||= @fallback_mission.name.to_s.downcase.scan(/[a-z0-9]+/)
    end

    def mission_scope
      scope = Mission.all
      scope = scope.joins(:operation).where(operations: { tenant_id: tenant.id }) if tenant
      scope = scope.where(operation:) if operation
      scope
    end

    def tenant
      @runtime_context&.tenant || @fallback_mission&.operation&.tenant || Current.tenant
    end

    def operation
      @runtime_context&.operation || @fallback_mission&.operation || Current.operation
    end
  end
end
