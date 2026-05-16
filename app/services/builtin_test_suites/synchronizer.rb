# frozen_string_literal: true

module BuiltinTestSuites
  class Synchronizer
    Result = Data.define(:created_keys, :restored_keys)

    def self.ensure_present!(keys: nil, tenant: Current.tenant || Tenant.default_tenant)
      new(keys:, restore: false, tenant:).call
    end

    def self.restore!(key, tenant: Current.tenant || Tenant.default_tenant)
      new(keys: [key], restore: true, tenant:).call
    end

    def self.restore_all!(tenant: Current.tenant || Tenant.default_tenant)
      new(restore: true, tenant:).call
    end

    def initialize(tenant: Current.tenant || Tenant.default_tenant, keys: nil, restore: false)
      @tenant = tenant
      @keys = Array(keys).compact.map(&:to_s).presence
      @restore = restore
    end

    def call
      definitions = load_definitions
      return Result.new(created_keys: [], restored_keys: []) if definitions.empty?

      @tenant.ensure_core_resources!
      ensure_target_agents!(definitions)

      created_keys = []
      restored_keys = []

      TestSuite.transaction do
        destroy_stale_suites!(definitions) if @keys.blank?
        definitions.each { |definition| sync_suite!(definition, created_keys:, restored_keys:) }
      end

      Result.new(created_keys:, restored_keys:)
    end

    private

    def load_definitions
      definitions = BuiltinTestSuites::DefinitionLoader.load_all
      return definitions if @keys.blank?

      definitions_by_key = definitions.index_by(&:key)
      missing = @keys - definitions_by_key.keys
      raise "Unknown builtin test suite keys: #{missing.join(", ")}" if missing.any?

      @keys.map { |key| definitions_by_key.fetch(key) }
    end

    def ensure_target_agents!(definitions)
      target_keys = definitions.map(&:target_builtin_agent_key).compact_blank.uniq
      BuiltinAgents::Synchronizer.ensure_present!(keys: target_keys, tenant: @tenant) if target_keys.any?
    end

    def destroy_stale_suites!(definitions)
      expected_keys = definitions.map(&:key)
      tenant_test_suites.builtin.find_each do |test_suite|
        test_suite.destroy! unless expected_keys.include?(test_suite.builtin_key)
      end
    end

    def sync_suite!(definition, created_keys:, restored_keys:)
      test_suite = find_or_initialize_suite(definition)
      created = test_suite.new_record?

      apply_locked_suite_attributes(test_suite, definition)
      apply_editable_suite_attributes(test_suite, definition) if created || @restore
      test_suite.save!

      sync_test_cases!(test_suite, definition)
      track_result!(definition.key, created, created_keys, restored_keys)
    end

    def find_or_initialize_suite(definition)
      tenant_test_suites.builtin.find { |suite| suite.builtin_key == definition.key } ||
        tenant_test_suites.find_by(name: definition.name) ||
        TestSuite.new
    end

    def apply_locked_suite_attributes(test_suite, definition)
      test_suite.assign_attributes(definition.locked_attributes)
      test_suite.agent = target_agent_for(definition)
      test_suite.mission = nil
      test_suite.evaluation_llm_connector = nil unless test_suite.evaluation_llm_connector_id?
    end

    def apply_editable_suite_attributes(test_suite, definition)
      test_suite.assign_attributes(definition.editable_attributes)
    end

    def sync_test_cases!(test_suite, definition)
      destroy_stale_test_cases!(test_suite, definition)

      definition.test_cases.each do |case_definition|
        test_case = find_or_initialize_test_case(test_suite, case_definition)
        created = test_case.new_record?

        test_case.assign_attributes(case_definition.locked_attributes(suite_key: definition.key,
                                                                      source_path: definition.source_path,))
        if created || @restore
          test_case.assign_attributes(case_definition.editable_attributes(default_fixture_key: definition.fixture_key))
        end
        test_case.save!
      end
    end

    def destroy_stale_test_cases!(test_suite, definition)
      expected_keys = definition.test_cases.map(&:key)
      test_suite.test_cases.builtin.reorder(nil).find_each do |test_case|
        test_case.destroy! unless expected_keys.include?(test_case.scenario_key)
      end
    end

    def find_or_initialize_test_case(test_suite, definition)
      test_suite.test_cases.builtin.find { |test_case| test_case.scenario_key == definition.key } ||
        test_suite.test_cases.find_by(scenario_key: definition.key) ||
        test_suite.test_cases.build
    end

    def target_agent_for(definition)
      key = definition.target_builtin_agent_key
      return nil if key.blank?

      Agent.find_builtin_by_key(key, tenant: @tenant) ||
        raise(ActiveRecord::RecordNotFound, "Builtin agent '#{key}' was not found.")
    end

    def tenant_test_suites
      TestSuite.where(agent_id: @tenant.agents.select(:id))
               .or(TestSuite.where(mission_id: @tenant.missions.select(:id)))
               .includes(:test_cases)
    end

    def track_result!(key, created, created_keys, restored_keys)
      created_keys << key if created
      restored_keys << key if @restore && !created
    end
  end
end
