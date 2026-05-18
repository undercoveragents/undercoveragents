# frozen_string_literal: true

module Tools
  module SqlQueryConnectorAccessors
    def connector
      return @connector_instance if defined?(@connector_instance) && @connector_instance&.id == connector_id

      @connector_instance = connector_id.present? ? find_connector(connector_id) : nil
    end

    def connector=(record)
      self.connector_id = record&.id
      @connector_instance = record
    end

    def llm_connector
      return @llm_connector_instance if cached_llm_connector?

      @llm_connector_instance = llm_connector_id.present? ? find_connector(llm_connector_id) : nil
    end

    def llm_connector=(record)
      self.llm_connector_id = record&.id
      @llm_connector_instance = record
    end

    private

    def cached_llm_connector?
      defined?(@llm_connector_instance) && @llm_connector_instance&.id == llm_connector_id
    end

    def connector_must_be_sql_database
      return if connector_id.blank?
      return errors.add(:connector, "must be an SQL Database connector") if connector.blank?
      return if connector.connector_type == "sql_database"

      errors.add(:connector, "must be an SQL Database connector")
    end

    def llm_connector_must_be_llm_provider
      return unless use_custom_llm_config?
      return if llm_connector_id.blank?
      return if llm_connector&.connector_type == "llm_provider"

      errors.add(:llm_connector_id, "must be an LLM Provider connector")
    end
  end
end
