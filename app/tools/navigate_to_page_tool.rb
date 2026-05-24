# frozen_string_literal: true

class NavigateToPageTool < RubyLLM::Tool
  DESCRIPTION = [
    "Point the admin UI to a supported page after you finish a create or update.",
    "This tool does not read page content or return record information, so never use it",
    "to inspect, verify, or gather information. Currently supports mission, agent, skill catalog,",
    "test suite, channel, automation trigger, and tool pages.",
  ].join(" ")
  RESOURCE_DESCRIPTION = [
    "The resource type for the page you want to show the user after the change.",
    "Supported values: 'mission', 'agent', 'skill_catalog', 'test_suite', 'channel', 'automation_trigger', or 'tool'.",
  ].join(" ")
  PAGE_DESCRIPTION = [
    "The destination page to show after the create/update work is complete.",
    "Missions support index, new, edit, and designer. Agents support index, new,",
    "show, and edit. Skill catalogs support index, new, show, and edit.",
    "Test suites support index, new, show, and edit.",
    "Channels support index, new, show, edit, and preview (client-channel only).",
    "Automation triggers support index, new, and edit.",
    "Tools support index, new, show, and edit.",
  ].join(" ")
  RECORD_PAGE_DESCRIPTION = "Required when pointing the user to a specific record page such as show, edit, " \
                            "and designer. Accepts a numeric ID or a slug."

  description DESCRIPTION

  param :resource, desc: RESOURCE_DESCRIPTION

  param :page, desc: PAGE_DESCRIPTION

  param :record_id, desc: RECORD_PAGE_DESCRIPTION, required: false

  def initialize(agent: nil, parent_chat: nil, mission: nil, ui_context: nil)
    super()
    @runtime_context = BuiltinTools::RuntimeContext.build(agent:, parent_chat:, mission:, ui_context:)
  end

  def name
    "navigate_to_page"
  end

  def description
    DESCRIPTION
  end

  def execute(resource:, page:, record_id: nil)
    manager = RuntimeRecords::Manager.new(@runtime_context)
    path = manager.navigation_path(resource:, page:, record_id:)
    navigated = RuntimeRecords::Navigation.broadcast!(chat: @runtime_context.chat, path:) == :broadcasted

    lines = [
      "Navigation target resolved for UI handoff only.",
      "- Path: `#{path}`",
      "- No page content or record data is returned by this tool.",
    ]
    lines << navigation_message(navigated)

    lines.join("\n")
  rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError, Pundit::NotAuthorizedError => e
    "Error: #{e.message}"
  rescue StandardError => e
    "Failed to navigate: #{e.message}"
  end

  private

  def navigation_message(navigated)
    if navigated
      return "Turbo navigation started. This only points the UI to the page; " \
             "the next turn will use the new page context."
    end

    if @runtime_context.chat&.application?
      return "Navigation was not broadcast. Open the returned path manually if you still need to show the updated page."
    end

    "Navigation is only broadcast from the shared application chat, and it never returns page contents."
  end
end
