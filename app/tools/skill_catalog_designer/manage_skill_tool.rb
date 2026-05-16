# frozen_string_literal: true

module SkillCatalogDesigner
  MANAGE_SKILL_ACTION_HANDLERS = {
    create: ->(tool, options) { tool.send(:create_skill, options[:skill_catalog_id], options[:attributes]) },
    update: ->(tool, options) { tool.send(:update_skill, options[:skill_id], options[:attributes]) },
    delete: ->(tool, options) { tool.send(:delete_skill, options[:skill_id], options[:confirm_destroy]) },
    restore: ->(tool, options) { tool.send(:restore_skill, options[:skill_id]) },
    import: ->(tool, options) { tool.send(:import_skill, options[:skill_catalog_id], options[:attachment_filename]) },
  }.freeze
  MANAGE_SKILL_ACTIONS = {
    "create" => :create,
    "update" => :update,
    "delete" => :delete,
    "restore" => :restore,
    "import" => :import,
  }.freeze
  MANAGE_SKILL_ATTRIBUTE_KEYS = [
    "name",
    "description",
    "instructions",
    "license",
    "compatibility",
    "allowed_tools",
    "metadata",
    "remove_resource_ids",
    "resource_directory",
    "use_current_message_attachments",
  ].freeze

  class ManageSkillTool < RubyLLM::Tool
    include AttachmentSupport
    include CurrentPageRefreshable
    include ManageSkillSupport
    include PolicyAuthorizable
    include SkillCatalogLookup

    include SkillLookup

    description "Create, update, delete, restore, or import a skill inside the current skill catalog."

    param :action,
          desc: "Skill action to run: 'create', 'update', 'delete', 'restore', or 'import'."

    param :skill_id,
          desc: "Required for update, delete, and restore. Accepts a numeric ID or exact skill name.",
          required: false

    param :skill_catalog_id,
          desc: "Required for create and import when no current skill catalog page is open. Accepts an ID or slug.",
          required: false

    param :attributes,
          desc: "Hash or JSON object string of skill attributes, including metadata and attachment/resource options.",
          required: false

    param :attachment_filename,
          desc: "Optional attachment filename from the latest user message when import needs one file.",
          required: false

    param :confirm_destroy,
          desc: "Must be true for delete actions. Only use delete when the user explicitly asked for it.",
          required: false

    def initialize(runtime_context:, current_skill: nil, current_skill_catalog: nil)
      super()
      @runtime_context = runtime_context
      @current_skill = current_skill
      @current_skill_catalog = current_skill_catalog
    end

    def name = "manage_skill"

    def execute(action:, **options)
      normalized_action = MANAGE_SKILL_ACTIONS[action.to_s]
      return unknown_action_message(action) unless normalized_action

      MANAGE_SKILL_ACTION_HANDLERS.fetch(normalized_action).call(self, options)
    rescue ActiveRecord::RecordInvalid => e
      "Error: #{e.record.errors.full_messages.to_sentence}"
    rescue ActiveRecord::RecordNotFound, ArgumentError, JSON::ParserError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing skill: #{e.message}"
    end

    private

    def create_skill(skill_catalog_id, raw_attributes)
      skill_catalog = resolve_skill_catalog(skill_catalog_id)
      return missing_skill_catalog_message if skill_catalog.nil?

      attributes = normalize_attributes(raw_attributes)
      return "Error: Provide attributes for create." if attributes.blank?

      skill = skill_catalog.skills.new(source_type: "manual")
      authorize_policy!(skill, :create?, user: @runtime_context.user)
      assign_skill_attributes(skill, attributes)

      Skill.transaction do
        skill.save!
        apply_resource_updates(skill, attributes)
      end

      refreshed = broadcast_current_page_refresh?
      success_message(skill:, action: "create", refreshed:)
    end

    def update_skill(skill_id, raw_attributes)
      skill = resolve_skill(skill_id)
      return missing_skill_message if skill.nil?

      attributes = normalize_attributes(raw_attributes)
      return "Error: Provide attributes for update." if attributes.blank?

      authorize_policy!(skill, :update?, user: @runtime_context.user)
      assign_skill_attributes(skill, attributes)

      Skill.transaction do
        skill.save!
        apply_resource_updates(skill, attributes)
      end

      refreshed = broadcast_current_page_refresh?
      success_message(skill:, action: "update", refreshed:)
    end

    def delete_skill(skill_id, confirm_destroy)
      skill = resolve_skill(skill_id)
      return missing_skill_message if skill.nil?
      return "Error: confirm_destroy must be true for delete actions." unless boolean(confirm_destroy)

      authorize_policy!(skill, :destroy?, user: @runtime_context.user)
      catalog = skill.skill_catalog
      skill_name = skill.name
      skill.destroy!
      refreshed = broadcast_current_page_refresh?

      [
        "Skill deleted successfully.",
        "- Skill: #{skill_name}",
        "- Catalog: #{catalog.name} (`#{catalog.id}`)",
        ("Current page refresh started to show the saved skill catalog." if refreshed),
      ].compact.join("\n")
    end

    def restore_skill(skill_id)
      skill = resolve_skill(skill_id)
      return missing_skill_message if skill.nil?

      authorize_policy!(skill, :restore?, user: @runtime_context.user)
      unless skill.builtin? && skill.skill_catalog.builtin?
        raise ArgumentError,
              "Skill '#{skill.name}' is not a built-in skill."
      end

      BuiltinSkills::Synchronizer.restore!(skill.skill_catalog.builtin_key, tenant:)
      restored_skill = restored_builtin_skill(skill)
      refreshed = broadcast_current_page_refresh?

      [
        "Skill action completed.",
        "- Skill: #{restored_skill.name} (`#{restored_skill.id}`)",
        "- Action: `restore`",
        "- Result: Built-in skill restored to the shipped defaults.",
        ("Current page refresh started to show the saved skill." if refreshed),
      ].compact.join("\n")
    end

    def import_skill(skill_catalog_id, attachment_filename)
      skill_catalog = resolve_skill_catalog(skill_catalog_id)
      return missing_skill_catalog_message if skill_catalog.nil?

      authorize_policy!(skill_catalog, :update?, user: @runtime_context.user)

      with_selected_upload(attachment_filename) do |upload, _attachment|
        result = Skills::ImportService.new(catalog: skill_catalog, upload:, mode: :single).call
        imported_skill = result.skills.first
        refreshed = broadcast_current_page_refresh?

        [
          "Skill action completed.",
          "- Skill: #{imported_skill.name} (`#{imported_skill.id}`)",
          "- Catalog: #{skill_catalog.name} (`#{skill_catalog.id}`)",
          "- Action: `import`",
          "- Result: Imported 1 skill from #{upload.original_filename}.",
          ("- Warnings: #{result.warnings.size}" if result.warnings.any?),
          ("Current page refresh started to show the saved skill catalog." if refreshed),
        ].compact.join("\n")
      end
    end
  end
end
