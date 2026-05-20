# frozen_string_literal: true

module RuntimeRecords
  class Manager
    Result = Data.define(:action, :definition, :record, :path)

    def initialize(context)
      @context = context
    end

    def create(resource:, attributes:)
      definition = Registry.fetch(resource)
      parsed_attributes = sanitize_attributes(definition, attributes)
      record = create_record(definition, parsed_attributes)

      Result.new(
        action: :create,
        definition:,
        record:,
        path: definition.path_for(definition.default_page_for(record:, context: @context), record:, context: @context),
      )
    end

    def update(resource:, record_id:, attributes:)
      definition = Registry.fetch(resource)
      record = find_record!(definition, record_id)
      parsed_attributes = sanitize_attributes(definition, attributes)

      authorize!(record, :update?)
      if definition.update_handler
        record = definition.update_handler.call(
          context: @context,
          definition:,
          record:,
          attributes: parsed_attributes,
        )
      else
        record.update!(parsed_attributes)
      end

      Result.new(action: :update, definition:, record:, path: nil)
    end

    def destroy(resource:, record_id:)
      definition = Registry.fetch(resource)
      record = find_record!(definition, record_id)

      authorize!(record, :destroy?)
      record.destroy!

      Result.new(
        action: :delete,
        definition:,
        record:,
        path: definition.path_for("index", record: nil, context: @context),
      )
    end

    def clone(resource:, record_id:)
      definition = Registry.fetch(resource)
      unless definition.clone_supported
        raise ArgumentError, "Clone is not supported for #{definition.label.downcase.pluralize}."
      end

      record = find_record!(definition, record_id)
      authorize!(record, :clone?)

      clone_result = Admin::CloneRecordService.call(record)
      raise ActiveRecord::RecordInvalid, clone_result.record unless clone_result.success?

      cloned_record = clone_result.record

      Result.new(
        action: :clone,
        definition:,
        record: cloned_record,
        path: definition.path_for(
          definition.default_page_for(record: cloned_record, context: @context),
          record: cloned_record,
          context: @context,
        ),
      )
    end

    def navigation_path(resource:, page:, record_id: nil)
      definition = Registry.fetch(resource)
      record = record_id.present? ? find_record!(definition, record_id) : nil

      definition.path_for(page, record:, context: @context)
    end

    private

    def create_record(definition, parsed_attributes)
      return create_record_with_handler(definition, parsed_attributes) if definition.create_handler

      build_record(definition, parsed_attributes).tap do |built_record|
        authorize!(built_record, :create?)
        built_record.save!
      end
    end

    def create_record_with_handler(definition, parsed_attributes)
      authorized_record = nil
      authorizer = lambda do |record, query|
        authorize!(record, query)
        authorized_record = record if query.to_sym == :create?
      end

      definition.model_class.transaction do
        record = definition.create_handler.call(
          context: @context,
          definition:,
          attributes: parsed_attributes,
          authorize: authorizer,
        )
        raise ArgumentError, "#{definition.label} create handler did not return a record." unless record

        authorize!(record, :create?) unless authorized_record.equal?(record)
        record
      end
    end

    def parse_hash(value)
      case value
      when nil
        {}
      when ActionController::Parameters
        value.to_unsafe_h.stringify_keys
      when Hash
        value.stringify_keys
      when String
        parse_string_hash(value)
      else
        raise ArgumentError, "Expected attributes to be a hash or JSON object string."
      end
    end

    def parse_string_hash(value)
      stripped = value.strip
      return {} if stripped.empty?

      parsed = JSON.parse(stripped)
      raise ArgumentError, "Expected a JSON object." unless parsed.is_a?(Hash)

      parsed.stringify_keys
    end

    def sanitize_attributes(definition, raw_attributes)
      attributes = parse_hash(raw_attributes)
      unknown_keys = attributes.keys - definition.permitted_attribute_keys

      if unknown_keys.any?
        joined_keys = unknown_keys.join(", ")
        raise ArgumentError, "Unknown #{definition.label.downcase} attributes: #{joined_keys}"
      end

      attributes
    end

    def build_record(definition, attributes)
      definition.model_class.new(
        definition.base_attributes_for(@context).merge(sanitize_attributes(definition, attributes)),
      )
    end

    def find_record!(definition, record_id)
      identifier = record_id.to_s.strip
      raise ArgumentError, "Provide record_id." if identifier.blank?

      scope = definition.scope_for(@context)
      scope.find_by(id: identifier) ||
        scope.find_by(slug: identifier) ||
        unique_name_match(scope, definition, identifier) ||
        missing_record!(definition, identifier)
    end

    def unique_name_match(scope, definition, identifier)
      model_class = definition.model_class
      return unless model_class.column_names.include?("name")

      table_name = model_class.table_name
      matches = scope.where("LOWER(#{table_name}.name) = ?", identifier.downcase).limit(2).to_a
      return matches.first if matches.one?
      return nil if matches.empty?

      message = "Multiple #{definition.label.downcase.pluralize} named '#{identifier}' were found. " \
                "Pass the numeric ID or slug instead."

      raise ActiveRecord::RecordNotFound, message
    end

    def missing_record!(definition, identifier)
      raise ActiveRecord::RecordNotFound, "#{definition.label} '#{identifier}' was not found."
    end

    def authorize!(record, query)
      policy_class = "#{record.class.name}Policy".safe_constantize
      raise ArgumentError, "Missing policy for #{record.class.name}." unless policy_class

      policy = policy_class.new(@context.user, record)
      return if policy.public_send(query)

      raise Pundit::NotAuthorizedError, (policy.denied_reason(query) || "Not allowed.")
    end
  end
end
