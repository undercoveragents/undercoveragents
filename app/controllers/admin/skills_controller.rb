# frozen_string_literal: true

module Admin
  class SkillsController < BaseController
    include BuiltinSkillCatalogSupport

    before_action :ensure_builtin_skill_catalogs!, if: :headquarter_operation?
    before_action :set_skill_catalog
    before_action :set_skill, only: [:show, :edit, :update, :destroy, :restore]

    def show
      authorize @skill
    end

    def new
      @skill = @skill_catalog.skills.new(source_type: "manual")
      authorize @skill
    end

    def edit
      authorize @skill
    end

    def create
      @skill = @skill_catalog.skills.new(source_type: "manual")
      authorize @skill
      apply_skill_attributes(@skill)

      if save_skill_with_resources(@skill)
        redirect_to admin_skill_catalog_skill_path(@skill_catalog, @skill), notice: t("skills.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @skill
      apply_skill_attributes(@skill)

      if save_skill_with_resources(@skill)
        redirect_to admin_skill_catalog_skill_path(@skill_catalog, @skill), notice: t("skills.updated")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @skill
      @skill.destroy!
      redirect_to admin_skill_catalog_path(@skill_catalog), notice: t("skills.deleted"), status: :see_other
    end

    def restore
      authorize @skill, :restore?
      raise ActiveRecord::RecordNotFound, "Not a builtin skill" unless @skill.builtin? && @skill_catalog.builtin?

      BuiltinSkills::Synchronizer.restore!(@skill_catalog.builtin_key, tenant: current_tenant)

      restored_catalog = restored_builtin_catalog(@skill_catalog.builtin_key)
      restored_skill_scope = restored_catalog.skills.builtin
      restored_skill = restored_skill_scope.where("source_metadata ->> 'builtin_key' = ?", @skill.builtin_key).first!

      redirect_to admin_skill_catalog_skill_path(restored_catalog, restored_skill), notice: t("skills.restored")
    end

    def import
      @skill = @skill_catalog.skills.new
      authorize @skill_catalog, :update?
    end

    def create_import
      authorize @skill_catalog, :update?
      @skill = @skill_catalog.skills.new
      upload = params[:archive]

      if upload.blank?
        flash.now[:alert] = t("skills.import_upload_required")
        render :import, status: :unprocessable_content
        return
      end

      result = Skills::ImportService.new(catalog: @skill_catalog, upload:, mode: :single).call
      imported_skill = result.skills.first

      redirect_to admin_skill_catalog_skill_path(@skill_catalog, imported_skill), notice: import_notice(result)
    rescue Skills::ImportService::ImportError => e
      flash.now[:alert] = e.message
      render :import, status: :unprocessable_content
    end

    private

    def set_skill_catalog
      @skill_catalog = scoped_skill_catalogs.friendly.find(params.expect(:skill_catalog_id))
    end

    def set_skill
      @skill = @skill_catalog.skills.find(params.expect(:id))
    end

    def apply_skill_attributes(skill)
      skill.assign_attributes(skill_params)

      metadata = parsed_metadata_json
      return if metadata != :invalid

      skill.errors.add(:metadata, "must contain valid JSON")
    end

    def skill_params
      params.expect(skill: [:name, :description, :instructions, :license, :compatibility, :allowed_tools])
    end

    def parsed_metadata_json
      raw = params.dig(:skill, :metadata_json)
      return {} if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      :invalid
    end

    def save_skill_with_resources(skill)
      metadata = parsed_metadata_json
      if metadata == :invalid
        skill.errors.add(:metadata, "must contain valid JSON") if skill.errors[:metadata].blank?
        return false
      end

      skill.metadata = metadata

      Skill.transaction do
        skill.save!
        remove_selected_resources(skill)
        upload_new_resources(skill)
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def remove_selected_resources(skill)
      resource_ids = Array(params.dig(:skill, :remove_resource_ids)).compact_blank.map(&:to_i)
      return if resource_ids.empty?

      skill.skill_resources.where(id: resource_ids).destroy_all
    end

    def upload_new_resources(skill)
      files = Array(params.dig(:skill, :resource_files)).grep(ActionDispatch::Http::UploadedFile)
      return if files.empty?

      directory = sanitize_resource_directory(params.dig(:skill, :resource_directory))

      files.each do |file|
        relative_path = [directory.presence, file.original_filename].compact.join("/")
        resource = skill.skill_resources.find_or_initialize_by(relative_path:)
        resource.file.attach(file)
        resource.save!
      end
    end

    def sanitize_resource_directory(value)
      value.to_s.tr("\\", "/").squeeze("/").gsub(%r{\A/+|/+$}, "")
    end

    def import_notice(result)
      skill = result.skills.first
      summary = [
        "Imported #{skill.name} into #{@skill_catalog.name}.",
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
