# frozen_string_literal: true

module Admin
  class MissionsController < BaseController
    include MissionRecordContext

    before_action :set_mission, only: [:designer, :edit, :update, :clone_record, :destroy]

    def index
      authorize Mission
      @missions = scoped_missions.includes(:operation).order(updated_at: :desc)
    end

    def new
      @mission = Mission.new(operation: current_operation)
      authorize @mission
    end

    # GET /admin/missions/:id/edit — metadata form (name, description)
    def edit
      authorize @mission
    end

    def create
      @mission = Mission.new(mission_form_params.merge(operation: current_operation))
      authorize @mission
      if @mission.save
        redirect_to designer_admin_mission_path(@mission)
      else
        render :new, status: :unprocessable_content
      end
    end

    # GET /admin/missions/:id/designer — visual canvas
    def designer
      authorize @mission, :designer?
      @llm_connectors = scoped_connectors.llm_providers.enabled.ordered
      @node_errors = Missions::NodeConfigValidator.validate_flow(@mission.flow_data)
      @latest_run = @mission.mission_runs.recent.first
      @recent_runs = @mission.mission_runs.recent.limit(10)
      @debug_state = build_debug_state(@latest_run)
    end

    # PATCH /admin/missions/:id — updates metadata
    def update
      authorize @mission
      if @mission.update(mission_form_params)
        redirect_to admin_missions_path, notice: t("missions.updated")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def clone_record
      authorize @mission, :clone?

      result = Admin::CloneRecordService.call(@mission)

      if result.success?
        redirect_to designer_admin_mission_path(result.record), notice: t("missions.cloned")
      else
        redirect_to designer_admin_mission_path(@mission), alert: result.errors.full_messages.to_sentence
      end
    end

    def destroy
      authorize @mission
      @mission.destroy
      redirect_to admin_missions_path, notice: t("missions.deleted"), status: :see_other
    end

    private

    def mission_form_params
      params.expect(mission: [:name, :description])
    end

    def build_debug_state(run)
      return unless run

      Missions::DebugRunState.new(mission: @mission, run:)
    end
  end
end
