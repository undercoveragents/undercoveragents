# frozen_string_literal: true

module CostDesigner
  class ManageCostLimitTool < RubyLLM::Tool
    include CostLimitLookup

    PERMITTED_ATTRIBUTES = [
      "name",
      "description",
      "target_type",
      "target_id",
      "target_key",
      "operation_id",
      "period",
      "amount_usd",
      "warning_threshold_percent",
      "enforcement_mode",
      "enabled",
    ].freeze

    description "Create, update, delete, or toggle cost limits in the current tenant."

    param :action, desc: "Action to perform: create, update, delete, or toggle."
    param :cost_limit_id,
          desc: "Required for update, delete, and toggle. Accepts numeric ID or exact name.",
          required: false
    param :attributes, desc: "Hash or JSON object with cost limit attributes for create or update.", required: false
    param :confirm_destroy, desc: "Must be true for delete.", required: false

    def initialize(runtime_context:)
      super()
      @runtime_context = runtime_context
    end

    def name = "manage_cost_limit"

    def execute(action:, cost_limit_id: nil, attributes: nil, confirm_destroy: false)
      case action.to_s
      when "create" then create_limit(attributes)
      when "update" then update_limit(cost_limit_id, attributes)
      when "delete" then delete_limit(cost_limit_id, confirm_destroy)
      when "toggle" then toggle_limit(cost_limit_id)
      else "Error: Unknown action '#{action}'. Use create, update, delete, or toggle."
      end
    rescue ActiveRecord::RecordInvalid => e
      "Error: #{e.record.errors.full_messages.to_sentence}"
    rescue ActiveRecord::RecordNotFound, ArgumentError, JSON::ParserError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    end

    private

    def create_limit(raw_attributes)
      limit = tenant.cost_limits.new(parsed_attributes(raw_attributes))
      authorize!(limit, :create?)
      limit.save!
      "Created cost limit `#{limit.id}` — #{limit.name}."
    end

    def update_limit(cost_limit_id, raw_attributes)
      limit = required_limit(cost_limit_id)
      authorize!(limit, :update?)
      limit.update!(parsed_attributes(raw_attributes))
      "Updated cost limit `#{limit.id}` — #{limit.name}."
    end

    def delete_limit(cost_limit_id, confirm_destroy)
      limit = required_limit(cost_limit_id)
      unless ActiveModel::Type::Boolean.new.cast(confirm_destroy)
        return "Error: confirm_destroy must be true for delete."
      end

      authorize!(limit, :destroy?)
      name = limit.name
      limit.destroy!
      "Deleted cost limit — #{name}."
    end

    def toggle_limit(cost_limit_id)
      limit = required_limit(cost_limit_id)
      authorize!(limit, :toggle?)
      limit.update!(enabled: !limit.enabled?)
      "#{limit.enabled? ? "Enabled" : "Disabled"} cost limit `#{limit.id}` — #{limit.name}."
    end

    def required_limit(cost_limit_id)
      limit = resolve_cost_limit(cost_limit_id)
      raise ArgumentError, "Provide cost_limit_id." unless limit

      limit
    end

    def parsed_attributes(raw_attributes)
      attributes = parse_hash(raw_attributes)
      unknown_keys = attributes.keys - PERMITTED_ATTRIBUTES
      raise ArgumentError, "Unknown cost limit attributes: #{unknown_keys.join(", ")}" if unknown_keys.any?

      attributes.transform_values(&:presence)
    end

    def parse_hash(value)
      case value
      when ActionController::Parameters then value.to_unsafe_h.stringify_keys
      when Hash then value.stringify_keys
      when String then parse_json_attributes(value)
      else raise ArgumentError, "Expected attributes to be a hash or JSON object string."
      end
    end

    def parse_json_attributes(value)
      JSON.parse(value).tap do |parsed|
        raise ArgumentError, "Expected a JSON object." unless parsed.is_a?(Hash)
      end
    end

    def authorize!(record, query)
      policy = CostLimitPolicy.new(@runtime_context.user, record)
      return if policy.public_send(query)

      raise Pundit::NotAuthorizedError, (policy.denied_reason(query) || "Not allowed.")
    end
  end
end
