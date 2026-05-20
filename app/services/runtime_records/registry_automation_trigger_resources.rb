# frozen_string_literal: true

module RuntimeRecords
  module RegistryAutomationTriggerResources
    AUTOMATION_TARGET_CLASSES = {
      "mission" => Mission,
      "rag_flow" => RagFlow,
    }.freeze

    private

    def register_automation_trigger
      register(
        "automation_trigger",
        label: "Automation Trigger",
        model_class: AutomationTrigger,
        permitted_attributes: RuntimeRecords::AUTOMATION_TRIGGER_PERMITTED_ATTRIBUTES,
        scope_resolver: method(:automation_trigger_scope),
        base_attributes: method(:automation_trigger_base_attributes),
        default_page: "edit",
        page_resolver: method(:automation_trigger_page_path),
        create_handler: method(:automation_trigger_create),
        update_handler: method(:automation_trigger_update),
      )
    end

    def automation_trigger_scope(context)
      operation = automation_trigger_operation(context)

      tenant_scope = AutomationTrigger.joins(:operation)
      tenant_scope = tenant_scope.where(operations: { tenant_id: context.tenant.id }) if context.tenant
      tenant_scope.where(operation:)
    end

    def automation_trigger_base_attributes(context)
      { "operation" => automation_trigger_operation(context) }
    end

    def automation_trigger_page_path(page, record:, context:)
      helpers = Rails.application.routes.url_helpers

      case page.to_s
      when "edit"
        raise ArgumentError, "Automation trigger page 'edit' requires a record." unless record

        case record.schedulable
        when Mission
          helpers.edit_admin_mission_automation_trigger_path(record.schedulable, record)
        when RagFlow
          helpers.edit_admin_rag_flow_automation_trigger_path(record.schedulable, record)
        else
          raise ArgumentError, "Unsupported automation target '#{record.schedulable.class.name}'."
        end
      when "index", "new"
        automation_trigger_collection_path(page:, record:, context:, helpers:)
      else
        raise ArgumentError, "Unknown page '#{page}' for automation_trigger. Use index, new, or edit."
      end
    end

    def automation_trigger_create(context:, attributes:, authorize:, **)
      target = resolve_automation_target!(context:, attributes:)
      trigger_attributes = attributes.except("target_type", "target_id")
      record = target.automation_triggers.new(trigger_attributes.merge("operation" => target.operation))
      authorize.call(record, :create?)
      record.save!
      record
    end

    def automation_trigger_update(context:, record:, attributes:, **)
      target_attrs = attributes.slice("target_type", "target_id").compact_blank
      if target_attrs.any?
        target = resolve_automation_target!(context:, attributes:)
        unless target == record.schedulable
          raise ArgumentError, "Automation trigger target cannot be changed once the trigger exists."
        end
      end

      record.update!(attributes.except("target_type", "target_id"))
      record
    end

    def resolve_automation_target!(context:, attributes:)
      current_target = automation_target_from_context(context)
      target_type = attributes["target_type"].presence || model_element(current_target)
      target_id = attributes["target_id"].presence || current_target&.id

      if target_type.blank? || target_id.blank?
        raise ArgumentError, "Provide target_type and target_id, or run this from a mission or RAG flow page."
      end

      model_class = automation_target_class!(target_type)
      find_automation_target!(model_class, target_id, context)
    end

    def automation_trigger_operation(context)
      operation = automation_target_from_context(context)&.operation || context.operation
      raise ArgumentError, "No current operation is available for automation triggers." unless operation

      operation
    end

    def automation_target_from_context(context)
      return context.mission if context.mission.is_a?(Mission)

      object = current_context_object(context)
      return unless object

      identifier = object["id"].presence || object["slug"].presence
      return if identifier.blank?

      resolve_context_target(object, identifier, context)
    end

    def scoped_runtime_target(model_class, context)
      model_class.where(operation: context.operation)
    end

    def automation_trigger_collection_path(page:, record:, context:, helpers:)
      target = automation_trigger_page_target!(record:, context:, page:)

      case target
      when Mission
        if page.to_s == "index"
          helpers.admin_mission_automation_triggers_path(target)
        else
          helpers.new_admin_mission_automation_trigger_path(target)
        end
      when RagFlow
        if page.to_s == "index"
          helpers.admin_rag_flow_automation_triggers_path(target)
        else
          helpers.new_admin_rag_flow_automation_trigger_path(target)
        end
      else
        raise ArgumentError, "Unsupported automation target '#{target.class.name}'."
      end
    end

    def automation_trigger_page_target!(record:, context:, page:)
      target = record&.schedulable || automation_target_from_context(context)
      raise_missing_automation_target!(page) unless target

      target
    end

    def raise_missing_automation_target!(page)
      raise ArgumentError, "Automation trigger page '#{page}' requires a mission or RAG flow context."
    end

    def model_element(record)
      record.class.model_name.element if record
    end

    def automation_target_class!(target_type)
      AUTOMATION_TARGET_CLASSES[target_type.to_s.underscore].tap do |model_class|
        raise ArgumentError, "Unsupported automation target '#{target_type}'." unless model_class
      end
    end

    def find_automation_target!(model_class, identifier, context)
      record = find_context_target(model_class, identifier, context)
      return record if record

      raise ActiveRecord::RecordNotFound, "#{model_class.model_name.human} '#{identifier}' was not found."
    end

    def find_context_target(model_class, identifier, context)
      scope = scoped_runtime_target(model_class, context)
      result = scope.find_by(id: identifier)
      result ||= scope.find_by(slug: identifier) if model_class.column_names.include?("slug")
      result
    end

    def current_context_object(context)
      object = context.ui_context&.dig("current_object")
      object if object.is_a?(Hash)
    end

    def resolve_context_target(object, identifier, context)
      model_class = context_target_model_class(object["class_name"].presence || object["type"].to_s)
      return unless model_class

      record = find_context_target(model_class, identifier, context)
      model_class == AutomationTrigger ? record&.schedulable : record
    end

    def context_target_model_class(class_name)
      case class_name
      when "Mission", Mission.model_name.human
        Mission
      when "RagFlow", RagFlow.model_name.human
        RagFlow
      when "AutomationTrigger", AutomationTrigger.model_name.human
        AutomationTrigger
      end
    end
  end
end
