# frozen_string_literal: true

module AgentAlpha
  class PageContext
    PURPOSE = "agent_alpha.page_context"
    DEFAULT_REFERENCE_TRIGGER = "#"
    VISIBLE_PARAM_KEYS = [
      "id", "slug", "mission_id", "agent_id", "tool_id", "channel_id", "connector_id",
      "skill_catalog_id", "rag_flow_id", "test_suite_id", "chat_id", "view",
      "stage", "suite_type", "module_type", "operation",
    ].freeze
    OBJECT_IVAR_PRIORITY = [
      "mission", "mission_run", "run", "test_suite", "agent", "tool", "connector", "rag_flow",
      "skill_catalog", "skill", "client", "api_client", "operation", "tenant", "chat", "user", "model",
      "plugin",
    ].freeze

    def self.issue_for(controller)
      user = controller.send(:current_user)
      return if user.blank?

      verifier.generate(
        {
          "user_id" => user.id,
          "tenant_id" => controller.send(:current_tenant)&.id,
          "payload" => new(controller).build,
        },
        purpose: PURPOSE,
      )
    end

    def self.verify(token, user:, tenant:)
      return if token.blank? || user.blank?

      verified = verifier.verified(token, purpose: PURPOSE)
      return unless verified.is_a?(Hash)
      return unless verified["user_id"] == user.id
      return unless verified["tenant_id"] == tenant&.id

      normalize_payload(verified["payload"])
    end

    def self.verifier
      @verifier ||= Rails.application.message_verifier(PURPOSE)
    end

    def self.normalize_payload(payload)
      return unless payload.is_a?(Hash)

      normalized = payload.deep_stringify_keys
      normalized["references"] = Array(normalized["references"]).filter_map do |reference|
        reference.is_a?(Hash) ? reference.deep_stringify_keys : nil
      end
      normalized["reference_trigger"] ||= DEFAULT_REFERENCE_TRIGGER
      normalized
    end

    def initialize(controller)
      @controller = controller
    end

    def build
      {
        "page" => page_payload,
        "current_object" => serialize_record(selected_object),
        "operation" => serialize_operation(controller.send(:current_operation)),
        "references" => [],
        "reference_trigger" => DEFAULT_REFERENCE_TRIGGER,
      }.compact
    end

    private

    attr_reader :controller

    def page_payload
      {
        "name" => page_name,
        "controller" => controller.controller_path,
        "action" => controller.action_name,
        "path" => controller.request.fullpath,
        "params" => visible_params.presence,
      }.compact
    end

    def page_name
      case controller.action_name
      when "index"
        controller.controller_name.humanize
      when "show"
        "#{resource_type_label} details"
      when "new", "create"
        "New #{resource_type_label}"
      when "edit", "update"
        "Edit #{resource_type_label}"
      else
        [resource_type_label, controller.action_name.humanize].compact.join(" ").strip
      end
    end

    def resource_type_label
      object = selected_object
      return object.class.model_name.human if object

      controller.controller_name.singularize.humanize
    end

    def selected_object
      @selected_object ||= begin
        candidates = candidate_object_names.filter_map do |name|
          controller.instance_variable_get("@#{name}")
        end

        candidates.find { |value| context_object?(value) }
      end
    end

    def candidate_object_names
      [
        controller.controller_name.singularize,
        controller.controller_path.split("/").last.singularize,
        *OBJECT_IVAR_PRIORITY,
      ].uniq
    end

    def context_object?(value)
      return false if value.blank?
      return false if value.is_a?(Array) || value.is_a?(Hash) || value.is_a?(String)

      value.respond_to?(:id) || value.respond_to?(:slug) || value.respond_to?(:name)
    end

    def serialize_record(record)
      return unless record

      {
        "type" => record.class.model_name.human,
        "class_name" => record.class.name,
        "id" => safe_value(record, :id),
        "slug" => safe_value(record, :slug),
        "label" => record_label(record),
      }.compact
    end

    def record_label(record)
      mission_run = mission_run_label(record)
      return mission_run if mission_run.present?

      [
        safe_value(record, :name),
        safe_value(record, :title),
        safe_value(record, :display_title),
        safe_value(record, :display_name),
        safe_value(record, :email),
        safe_value(record, :slug),
      ].find(&:present?) || "#{record.class.model_name.human} ##{record.id}"
    end

    def mission_run_label(record)
      return unless record.instance_of?(::MissionRun)
      return unless record.respond_to?(:mission) && record.mission.present?

      "#{record.mission.name} run ##{record.id}"
    end

    def safe_value(record, method_name)
      return unless record.respond_to?(method_name)

      record.public_send(method_name).presence
    rescue StandardError
      nil
    end

    def serialize_operation(operation)
      return unless operation

      {
        "id" => operation.id,
        "name" => operation.name,
        "slug" => operation.slug,
      }
    end

    def visible_params
      controller.params.to_unsafe_h.slice(*VISIBLE_PARAM_KEYS).compact_blank
    end
  end
end
