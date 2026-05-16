# frozen_string_literal: true

module SkillCatalogDesigner
  class ManageSkillCatalogActionTool < RubyLLM::Tool
    include AttachmentSupport
    include CurrentPageRefreshable
    include ManageSkillCatalogActionSupport
    include PolicyAuthorizable
    include SkillCatalogLookup

    ACTION_HANDLERS = {
      restore: ->(tool, options) { tool.send(:restore_catalog, options[:skill_catalog_id]) },
      restore_defaults: ->(tool, _options) { tool.send(:restore_defaults) },
      attach_agent: ->(tool, options) { tool.send(:attach_agent, options[:skill_catalog_id], options[:agent_id]) },
      detach_agent: ->(tool, options) { tool.send(:detach_agent, options[:skill_catalog_id], options[:agent_id]) },
      import_collection: lambda do |tool, options|
        tool.send(:import_collection, options[:skill_catalog_id], options[:attachment_filename])
      end,
    }.freeze

    ACTIONS = {
      "restore" => :restore,
      "restore_defaults" => :restore_defaults,
      "attach_agent" => :attach_agent,
      "detach_agent" => :detach_agent,
      "import_collection" => :import_collection,
      "import" => :import_collection,
    }.freeze

    description "Run skill catalog admin actions such as import, restore, and agent assignment."

    param :action,
          desc: "Skill catalog action to run: restore, restore_defaults, attach_agent, detach_agent, or import."

    param :skill_catalog_id,
          desc: "Optional numeric ID or slug. Omit to act on the current skill catalog from page context.",
          required: false

    param :agent_id,
          desc: "Required for attach_agent and detach_agent. Accepts a numeric ID or slug.",
          required: false

    param :attachment_filename,
          desc: "Optional attachment filename from the latest user message when import_collection needs one file.",
          required: false

    def initialize(runtime_context:, current_skill_catalog: nil)
      super()
      @runtime_context = runtime_context
      @current_skill_catalog = current_skill_catalog
    end

    def name = "manage_skill_catalog_action"

    def execute(action:, **options)
      normalized_action = ACTIONS[action.to_s]
      return unknown_action_message(action) unless normalized_action

      ACTION_HANDLERS.fetch(normalized_action).call(self, options)
    rescue ActiveRecord::RecordInvalid => e
      "Error: #{e.record.errors.full_messages.to_sentence}"
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing skill catalog action: #{e.message}"
    end

    private

    def restore_catalog(skill_catalog_id)
      skill_catalog = resolve_skill_catalog(skill_catalog_id)
      return missing_skill_catalog_message if skill_catalog.nil?

      authorize_policy!(skill_catalog, :restore?, user: @runtime_context.user)
      unless skill_catalog.builtin?
        raise ArgumentError,
              "Skill catalog '#{skill_catalog.name}' is not a built-in skill catalog."
      end

      BuiltinSkills::Synchronizer.restore!(skill_catalog.builtin_key, tenant:)
      restored_catalog = restored_builtin_catalog(skill_catalog.builtin_key)
      refreshed = broadcast_current_page_refresh?

      catalog_action_message(
        skill_catalog: restored_catalog,
        action: "restore",
        refreshed:,
        result: "Built-in skill catalog restored to the shipped defaults.",
      )
    end

    def restore_defaults
      authorize_policy!(SkillCatalog, :restore_defaults?, user: @runtime_context.user)

      result = BuiltinSkills::Synchronizer.restore_all!(tenant:)
      count = result.restored_keys.size + result.created_keys.size
      refreshed = broadcast_current_page_refresh?

      [
        "Skill catalog action completed.",
        "- Action: `restore_defaults`",
        "- Result: Restored #{count} built-in skill #{"catalog".pluralize(count)}.",
        ("Current page refresh started to show the saved skill catalogs." if refreshed),
      ].compact.join("\n")
    end

    def attach_agent(skill_catalog_id, agent_id)
      skill_catalog = resolve_skill_catalog(skill_catalog_id)
      return missing_skill_catalog_message if skill_catalog.nil?
      raise ArgumentError, "Provide agent_id for attach_agent." if agent_id.blank?

      authorize_policy!(skill_catalog, :attach_agent?, user: @runtime_context.user)
      agent = resolve_agent!(agent_id, selectable: true)

      agent.skill_catalog_ids = (agent.skill_catalog_ids + [skill_catalog.id]).uniq
      agent.save!
      refreshed = broadcast_current_page_refresh?

      catalog_action_message(skill_catalog:, action: "attach_agent", refreshed:, agent:)
    end

    def detach_agent(skill_catalog_id, agent_id)
      skill_catalog = resolve_skill_catalog(skill_catalog_id)
      return missing_skill_catalog_message if skill_catalog.nil?
      raise ArgumentError, "Provide agent_id for detach_agent." if agent_id.blank?

      authorize_policy!(skill_catalog, :detach_agent?, user: @runtime_context.user)
      agent = resolve_agent!(agent_id, selectable: false)

      agent.skill_catalog_ids = agent.skill_catalog_ids - [skill_catalog.id]
      agent.save!
      refreshed = broadcast_current_page_refresh?

      catalog_action_message(skill_catalog:, action: "detach_agent", refreshed:, agent:)
    end

    def import_collection(skill_catalog_id, attachment_filename)
      skill_catalog = resolve_skill_catalog(skill_catalog_id)
      return missing_skill_catalog_message if skill_catalog.nil?

      authorize_policy!(skill_catalog, :create_import?, user: @runtime_context.user)

      with_selected_upload(attachment_filename) do |upload, _attachment|
        result = Skills::ImportService.new(catalog: skill_catalog, upload:, mode: :collection).call
        refreshed = broadcast_current_page_refresh?
        imported_count = result.skills.size

        [
          "Skill catalog action completed.",
          "- Skill Catalog: #{skill_catalog.name} (`#{skill_catalog.id}`)",
          "- Action: `import_collection`",
          "- Result: Imported #{imported_count} #{"skill".pluralize(imported_count)} from #{upload.original_filename}.",
          ("- Warnings: #{result.warnings.size}" if result.warnings.any?),
          ("Current page refresh started to show the saved skill catalog." if refreshed),
        ].compact.join("\n")
      end
    end

    def unknown_action_message(action)
      [
        "Error: Unknown action '#{action}'.",
        "Use restore, restore_defaults, attach_agent, detach_agent, or import_collection.",
      ].join(" ")
    end
  end
end
