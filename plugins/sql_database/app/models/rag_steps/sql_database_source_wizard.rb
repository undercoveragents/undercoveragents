# frozen_string_literal: true

module RagSteps
  module SqlDatabaseSourceWizard
    extend ActiveSupport::Concern

    def generated_query
      return if selected_object_name.blank? || content_column.blank?

      columns = [content_column, *Array(metadata_columns), incremental_column].compact.uniq

      sql = "SELECT #{columns.map { |column| quote_identifier(column) }.join(", ")} " \
            "FROM #{qualified_source_name}"
      sql += " LIMIT #{record_limit.to_i}" if record_limit.present?
      sql
    end

    private

    def normalize_wizard_state
      normalize_string_attributes(:source_mode, :selected_object_name, :selected_object_type, :content_column,
                                  :incremental_column,)
      self.query = normalized_query_text
      self.metadata_columns = metadata_columns
      clear_object_selection_for_query_mode
    end

    def build_query_for_selected_object
      self.query = generated_query
    end

    def query_source_must_be_valid
      return if skip_query_validation?

      result = source_inspector.validate_query(query)
      return errors.add(:query, result.message) unless result.success?

      validate_selected_columns(result.columns)
    end

    def table_source_must_exist
      return if skip_table_lookup?

      result = source_inspector.schema_options
      return errors.add(:base, result.message) unless result.success?

      apply_selected_object!(result.objects.find { |object| object["name"] == selected_object_name })
    end

    def validate_selected_columns(columns)
      errors.add(:content_column, "was not found in the selected source") if column_missing?(content_column, columns)
      Array(metadata_columns).each do |column|
        next unless column_missing?(column, columns)

        errors.add(:metadata_columns, "contains '#{column}', which was not found")
      end
      return unless column_missing?(incremental_column, columns)

      errors.add(:incremental_column, "was not found in the selected source")
    end

    def column_missing?(column_name, columns)
      column_name.present? && columns.exclude?(column_name)
    end

    def normalize_string_attributes(*attribute_names)
      attribute_names.each do |attribute_name|
        public_send("#{attribute_name}=", normalized_string(public_send(attribute_name)))
      end
    end

    def normalized_query_text
      normalized_string(query)&.sub(/;\s*\z/, "")&.presence
    end

    def normalized_string(value)
      value.to_s.strip.presence
    end

    def clear_object_selection_for_query_mode
      return unless query_mode?

      self.selected_object_name = nil
      self.selected_object_type = nil
    end

    def skip_query_validation?
      connector.blank? || errors[:connector_id].any? || errors[:query].any? || query.blank?
    end

    def skip_table_lookup?
      connector.blank? || errors[:connector_id].any? || errors[:selected_object_name].any?
    end

    def apply_selected_object!(selected_object)
      return errors.add(:selected_object_name, "must match an existing table or view") unless selected_object

      self.selected_object_type ||= selected_object["type"]
      validate_selected_columns(Array(selected_object["columns"]).pluck("name"))
    end

    def qualified_source_name
      schema_name = connector&.schema_name.to_s.strip.presence
      [schema_name, selected_object_name].compact.map { |name| quote_identifier(name) }.join(".")
    end

    def quote_identifier(value)
      %("#{value.to_s.gsub('"', '""')}")
    end

    def source_inspector
      @source_inspector ||= Rag::SqlDatabaseSourceInspector.new(connector)
    end
  end
end
