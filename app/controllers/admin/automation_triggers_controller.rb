# frozen_string_literal: true

module Admin
  class AutomationTriggersController < BaseController
    include AutomatableRecordContext

    TRIGGER_TYPES = [
      {
        key: "schedule",
        label: "Schedule",
        icon: "fa-solid fa-clock",
        description: "Run the record automatically from a cron expression and timezone.",
      },
      {
        key: "webhook",
        label: "Webhook",
        icon: "fa-solid fa-link",
        description: "Expose a stable external endpoint protected by a rotatable secret.",
      },
    ].freeze

    before_action :set_schedulable
    before_action :set_automation_trigger, only: [:edit, :update, :destroy, :regenerate_secret]

    def index
      authorize AutomationTrigger
      @automation_triggers = automation_trigger_association.includes(:last_result_record).ordered
    end

    def new
      requested_type = requested_trigger_type
      return render_type_selection unless requested_type

      @automation_trigger = automation_trigger_association.new(
        operation: @schedulable.operation,
        trigger_type: requested_type,
        enabled: true,
        timezone: "UTC",
      )
      authorize @automation_trigger
    end

    def edit
      authorize @automation_trigger
    end

    def create
      @automation_trigger = automation_trigger_association.new(
        automation_trigger_create_params.merge(operation: @schedulable.operation),
      )
      authorize @automation_trigger

      if @automation_trigger.save
        store_webhook_secret_flash(@automation_trigger.raw_webhook_secret) if @automation_trigger.trigger_webhook?
        redirect_to edit_polymorphic_path([:admin, @schedulable, @automation_trigger]),
                    notice: t("automation_triggers.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @automation_trigger

      if @automation_trigger.update(automation_trigger_update_params)
        redirect_to edit_polymorphic_path([:admin, @schedulable, @automation_trigger]),
                    notice: t("automation_triggers.updated")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @automation_trigger

      @automation_trigger.destroy!
      redirect_to polymorphic_path([:admin, @schedulable, :automation_triggers]),
                  notice: t("automation_triggers.deleted"),
                  status: :see_other
    end

    def regenerate_secret
      authorize @automation_trigger

      store_webhook_secret_flash(@automation_trigger.regenerate_webhook_secret!)
      redirect_to edit_polymorphic_path([:admin, @schedulable, @automation_trigger]),
                  notice: t("automation_triggers.secret_regenerated")
    end

    private

    def set_automation_trigger
      @automation_trigger = automation_trigger_association.find(params.expect(:id))
    end

    def requested_trigger_type
      type = params[:type].presence ||
             params.dig(:automation_trigger, :trigger_type).presence ||
             params.dig(:mission_trigger, :trigger_type).presence
      AutomationTrigger.trigger_types.key?(type) ? type : nil
    end

    def render_type_selection
      authorize AutomationTrigger
      @trigger_types = TRIGGER_TYPES
      render :new
    end

    def automation_trigger_create_params
      params.expect(trigger_params_key => [:name, :trigger_type, :enabled, :cron_expression, :timezone, :payload])
    end

    def automation_trigger_update_params
      params.expect(trigger_params_key => [:name, :enabled, :cron_expression, :timezone, :payload])
    end

    def store_webhook_secret_flash(secret)
      flash[:automation_trigger_webhook_secret] = secret
      flash[:mission_trigger_webhook_secret] = secret if @schedulable.is_a?(Mission)
    end

    def automation_trigger_association
      @schedulable.is_a?(Mission) ? @schedulable.mission_triggers : @schedulable.automation_triggers
    end

    def trigger_params_key
      params[:automation_trigger].present? ? :automation_trigger : :mission_trigger
    end
  end
end
