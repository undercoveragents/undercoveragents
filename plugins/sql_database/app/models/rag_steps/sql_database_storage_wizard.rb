# frozen_string_literal: true

module RagSteps
  module SqlDatabaseStorageWizard
    extend ActiveSupport::Concern

    def existing_tables_mode?
      storage_mode == "existing"
    end

    def new_tables_mode?
      storage_mode == "new"
    end

    private

    def normalize_wizard_state
      normalize_string_attributes(:storage_mode, :documents_table, :chunks_table, :content_field,
                                  :embedding_field, :document_reference_field,)
      self.auto_create_tables = true if new_tables_mode?
      self.auto_create_tables = false if existing_tables_mode?
      self.metadata_field_mappings = metadata_field_mappings
      self.metadata_column_types = metadata_column_types
    end

    def table_names_must_differ
      return if documents_table.blank? || chunks_table.blank?
      return unless documents_table == chunks_table

      errors.add(:chunks_table, "must be different from documents table")
    end

    def existing_tables_configuration_must_be_valid
      return if skip_existing_table_validation?

      result = storage_inspector.validate_existing_tables(existing_tables_validation_payload)
      return if result.success?

      apply_existing_table_issues(result)
    end

    def skip_existing_table_validation?
      connector.blank? || connector_errors? || storage_field_errors?
    end

    def connector_errors?
      errors[:connector_id].any?
    end

    def storage_field_errors?
      [:documents_table, :chunks_table, :content_field, :embedding_field, :document_reference_field].any? do |field|
        errors[field].any?
      end
    end

    def existing_tables_validation_payload
      {
        documents_table:,
        chunks_table:,
        content_field:,
        embedding_field:,
        document_reference_field:,
        metadata_field_mappings:,
      }
    end

    def apply_existing_table_issues(result)
      return errors.add(:base, result.message) if result.issues.blank?

      result.issues.each do |issue|
        errors.add(issue[:field], issue[:message])
      end
    end

    def normalize_string_attributes(*attribute_names)
      attribute_names.each do |attribute_name|
        public_send("#{attribute_name}=", normalized_string(public_send(attribute_name)))
      end
    end

    def normalized_string(value)
      value.to_s.strip.presence
    end

    def storage_inspector
      @storage_inspector ||= Rag::SqlDatabaseStorageInspector.new(connector)
    end
  end
end
