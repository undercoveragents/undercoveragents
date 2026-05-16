# frozen_string_literal: true

module Admin
  class SkillCatalogsController < BaseController
    include BuiltinSkillCatalogSupport

    before_action :ensure_builtin_skill_catalogs!, if: :headquarter_operation?
    before_action :set_skill_catalog, only: [:show, :edit, :update, :destroy, :restore, :attach_agent, :detach_agent]

    def index
      authorize SkillCatalog
      @skill_catalogs = scoped_skill_catalogs.ordered.to_a
      SkillCatalog.preload_index_metrics(@skill_catalogs)
    end

    def show = authorize(@skill_catalog) && load_show_data

    def new
      @skill_catalog = SkillCatalog.new
      authorize @skill_catalog
    end

    def edit
      authorize @skill_catalog
    end

    def create
      @skill_catalog = SkillCatalog.new(operation: current_operation)
      authorize @skill_catalog
      @skill_catalog.assign_attributes(skill_catalog_params)

      if @skill_catalog.save
        redirect_to admin_skill_catalog_path(@skill_catalog), notice: t("skill_catalogs.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @skill_catalog

      if @skill_catalog.update(skill_catalog_params)
        redirect_to admin_skill_catalog_path(@skill_catalog), notice: t("skill_catalogs.updated")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @skill_catalog
      @skill_catalog.destroy!
      redirect_to admin_skill_catalogs_path, notice: t("skill_catalogs.deleted"), status: :see_other
    end

    def restore
      authorize @skill_catalog, :restore?
      raise ActiveRecord::RecordNotFound, "Not a builtin skill catalog" unless @skill_catalog.builtin?

      BuiltinSkills::Synchronizer.restore!(@skill_catalog.builtin_key, tenant: current_tenant)
      redirect_to admin_skill_catalog_path(restored_builtin_catalog(@skill_catalog.builtin_key)),
                  notice: t("skill_catalogs.restored")
    end

    def restore_defaults
      authorize SkillCatalog, :restore_defaults?
      result = BuiltinSkills::Synchronizer.restore_all!(tenant: current_tenant)
      count = result.restored_keys.size + result.created_keys.size
      redirect_to admin_skill_catalogs_path, notice: t("skill_catalogs.restored_all", count:)
    end

    def import
      @skill_catalog = SkillCatalog.new
      authorize @skill_catalog
      load_import_data
    end

    def create_import
      load_import_data
      target_mode = import_target_mode
      upload = params[:archive]

      return render_missing_import_upload(target_mode) if upload.blank?

      @skill_catalog = resolve_import_target(target_mode)
      authorize_import_target!
      return unless prepare_import_target?

      result = import_collection!(upload)

      redirect_to admin_skill_catalog_path(@skill_catalog), notice: import_notice(result)
    rescue Skills::ImportService::ImportError => e
      flash.now[:alert] = e.message
      render :import, status: :unprocessable_content
    end

    def attach_agent
      authorize @skill_catalog, :update?
      agent = scoped_agents.enabled.selectable.find(params.expect(:agent_id))
      agent.skill_catalog_ids = (agent.skill_catalog_ids + [@skill_catalog.id]).uniq

      if agent.save
        redirect_to admin_skill_catalog_path(@skill_catalog), notice: t("skill_catalogs.agent_attached")
      else
        load_show_data
        flash.now[:alert] = agent.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
      end
    end

    def detach_agent
      authorize @skill_catalog, :update?
      agent = scoped_agents.find(params.expect(:agent_id))
      agent.skill_catalog_ids = agent.skill_catalog_ids - [@skill_catalog.id]
      agent.save!

      redirect_to admin_skill_catalog_path(@skill_catalog), notice: t("skill_catalogs.agent_detached"),
                                                            status: :see_other
    end

    private

    def set_skill_catalog
      @skill_catalog = scoped_skill_catalogs.friendly.find(params.expect(:id))
    end

    def skill_catalog_params
      params.fetch(:skill_catalog, {}).permit(:name, :description)
    end

    def load_show_data
      @skills = @skill_catalog.skills.includes(:skill_resources).ordered
      @assigned_agents = @skill_catalog.assigned_agents
      @available_agents = scoped_agents.enabled.selectable.ordered.where.not(id: @assigned_agents.select(:id))
    end

    def load_import_data
      @existing_catalogs = scoped_skill_catalogs.ordered
    end

    def import_target_mode
      params.expect(:target_mode).presence_in(["new", "existing"]) || "new"
    end

    def render_missing_import_upload(target_mode)
      @skill_catalog = SkillCatalog.new(skill_catalog_params) if target_mode == "new"
      flash.now[:alert] = t("skill_catalogs.import_upload_required")
      render :import, status: :unprocessable_content
    end

    def authorize_import_target!
      authorize @skill_catalog, @skill_catalog.persisted? ? :update? : :create?
    end

    def prepare_import_target?
      return true unless @skill_catalog.new_record?

      @skill_catalog.assign_attributes(skill_catalog_params)
      return true if @skill_catalog.valid?

      render :import, status: :unprocessable_content
      false
    end

    def import_collection!(upload)
      SkillCatalog.transaction do
        @skill_catalog.save! if @skill_catalog.new_record?
        Skills::ImportService.new(catalog: @skill_catalog, upload:, mode: :collection).call
      end
    end

    def resolve_import_target(target_mode)
      if target_mode == "existing"
        scoped_skill_catalogs.friendly.find(params.require(:target_catalog_id))
      else
        SkillCatalog.new(operation: current_operation)
      end
    end

    def import_notice(result)
      summary = [
        "Imported #{result.skills.size} #{"skill".pluralize(result.skills.size)} into #{@skill_catalog.name}.",
        warning_summary(result.warnings),
      ].compact
      summary.join(" ")
    end

    def warning_summary(warnings)
      return unless warnings.any?

      "#{warnings.size} warning#{"s" if warnings.size != 1}."
    end
  end
end
