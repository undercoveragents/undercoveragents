# frozen_string_literal: true

module Admin
  class MissionsController < BaseController
    include MissionRecordContext

    before_action :set_mission, only: [:designer, :edit, :update, :duplicate, :destroy]

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

    def duplicate
      authorize @mission, :duplicate?

      duplicate = @mission.dup
      duplicate.name = duplicate_name_for(@mission.operation.missions, @mission.name)
      duplicate.flow_data = @mission.flow_data.deep_dup
      duplicate.flow_undo_history = []
      duplicate.flow_redo_history = []

      if duplicate.save
        redirect_to edit_admin_mission_path(duplicate), notice: t("missions.duplicated")
      else
        redirect_to edit_admin_mission_path(@mission), alert: duplicate.errors.full_messages.to_sentence
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
