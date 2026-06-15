# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength, Metrics/ModuleLength, Metrics/AbcSize
module BuiltinTools
  # Registers every app-level builtin tool with BuiltinTools::Registry.
  # Called from config/initializers/builtin_tools.rb on every reloader
  # `to_prepare` cycle so definitions survive dev code reloads.
  module Registrations
    ADMIN_RECORDS_GROUP_TITLE = "Managing records"
    AGENT_DESIGNER_GROUP_TITLE = "Working on the agent configuration"
    CHANNEL_DESIGNER_GROUP_TITLE = "Working on the channel configuration"
    CLIENT_DESIGNER_GROUP_TITLE = "Working on the client configuration"
    COST_DESIGNER_GROUP_TITLE = "Working on cost controls"
    MISSION_DESIGNER_GROUP_TITLE = "Working on the mission flow"
    RESOURCE_DISCOVERY_GROUP_TITLE = "Looking up configuration resources"
    SKILL_CATALOG_DESIGNER_GROUP_TITLE = "Working on the skill catalog"
    TEST_SUITE_DESIGNER_GROUP_TITLE = "Working on test suites"
    TOOL_DESIGNER_GROUP_TITLE = "Working on the tool configuration"
    WEB_RESEARCH_GROUP_TITLE = "Researching the web"

    module_function

    def register_all!
      Registry.definitions.clear

      register_resource_tools
      register_web_tools
      register_mission_designer_tools
      register_agent_designer_tools
      register_channel_designer_tools
      register_skill_catalog_designer_tools
      register_test_suite_designer_tools
      register_client_designer_tools
      register_cost_designer_tools
      register_tool_designer_tools
      register_record_admin_tools
      register_plugin_builtin_tools
    end

    def tool_call_presentation(running_messages:, complete_messages:,
                               running_mode: "rotate", running_interval_ms: 1600,
                               group_title: nil)
      {
        running_messages:,
        complete_messages:,
        running_mode:,
        running_interval_ms:,
        group_title:,
      }
    end

    def node_catalog_presentation
      tool_call_presentation(
        running_messages: [
          "Scanning the available node catalog…",
          "Collecting palette metadata…",
          "Assembling the latest node registry…",
        ],
        complete_messages: [
          "Node catalog loaded.",
          "Available node types are ready.",
          "Palette metadata collected.",
        ],
        group_title: MISSION_DESIGNER_GROUP_TITLE,
      )
    end

    def resource_catalog_presentation
      tool_call_presentation(
        running_messages: [
          "Collecting available resource IDs…",
          "Loading shared configuration references…",
          "Scanning the reusable resource catalog…",
        ],
        complete_messages: [
          "Resource IDs loaded.",
          "Shared configuration references are ready.",
          "Reusable resource catalog collected.",
        ],
        group_title: RESOURCE_DISCOVERY_GROUP_TITLE,
      )
    end

    def designer_runtime_context(agent:, parent_chat:, mission:, ui_context:)
      BuiltinTools::RuntimeContext.build(agent:, parent_chat:, mission:, ui_context:)
    end

    def register_resource_tools
      Registry.register(
        "resources.list_resources",
        name: "List Resources",
        description: "List operation-scoped resource IDs and values for one or more kinds used by designer tools.",
        visible_in_headquarter: true,
        runtime_name: "list_resources",
        icon: "fa-solid fa-layer-group",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: resource_catalog_presentation,
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        ListResourcesTool.new(
          tool_context[:mission],
          runtime_context:,
          current_agent: tool_context[:agent],
        )
      end
    end

    def register_web_tools
      Registry.register(
        "web.web_search",
        name: "Web Search",
        description: "Safely search the public web through a plugin-backed search client.",
        visible_in_headquarter: true,
        user_assignable: true,
        configuration_hint: "Uses the configured web-search provider; provider credentials stay on " \
                            "connector/plugin settings.",
        runtime_name: "web_search",
        icon: "fa-solid fa-globe",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Searching the public web…",
            "Using the configured public search client…",
            "Collecting relevant public URLs…",
          ],
          complete_messages: [
            "Web search completed.",
            "Relevant public URLs are ready.",
            "Search results collected safely.",
          ],
          group_title: WEB_RESEARCH_GROUP_TITLE,
        ),
      ) { |**| WebSearchTool.new }

      Registry.register(
        "web.web_fetch",
        name: "Web Fetch",
        description: "Safely fetch a very small number of public pages and return focused snippets.",
        visible_in_headquarter: true,
        user_assignable: true,
        runtime_name: "web_fetch",
        icon: "fa-solid fa-file-lines",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Fetching focused public pages…",
            "Downloading only capped text content…",
            "Extracting the smallest useful page snippets…",
          ],
          complete_messages: [
            "Web fetch completed.",
            "Focused public snippets are ready.",
            "Page fetch completed safely.",
          ],
          group_title: WEB_RESEARCH_GROUP_TITLE,
        ),
      ) { |**| WebFetchTool.new }
    end

    def register_mission_designer_tools
      Registry.register(
        "mission_designer.read_flow",
        name: "Read Mission Flow",
        description: "Inspect the current mission nodes, edges, and validation state.",
        visible_in_headquarter: true,
        runtime_name: "read_mission_flow",
        icon: "fa-solid fa-diagram-project",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current workflow graph…",
            "Collecting nodes, edges, and ports…",
            "Checking the latest validation state…",
          ],
          complete_messages: [
            "Mission flow snapshot loaded.",
            "Workflow graph is ready.",
            "Current flow state captured.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |agent: nil, parent_chat: nil, mission: nil, ui_context: nil, **|
        runtime_context = designer_runtime_context(agent:, parent_chat:, mission:, ui_context:)
        MissionDesigner::ReadFlowTool.new(mission, runtime_context:)
      end

      Registry.register(
        "mission_designer.list_node_types",
        name: "List Node Types",
        description: "List all mission node types that can be added to a workflow.",
        visible_in_headquarter: true,
        runtime_name: "list_node_types",
        icon: "fa-solid fa-list",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: node_catalog_presentation,
      ) { |**| MissionDesigner::ListNodeTypesTool.new }

      Registry.register(
        "mission_designer.node_type_info",
        name: "Node Type Info",
        description: "Show detailed configuration guidance for one or more mission node types.",
        visible_in_headquarter: true,
        runtime_name: "get_node_type_info",
        icon: "fa-solid fa-circle-info",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Looking up node guidance…",
            "Gathering field and port details…",
            "Opening the node configuration playbook…",
          ],
          complete_messages: [
            "Node guidance is ready.",
            "Configuration details collected.",
            "Node type info loaded.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) { |**| MissionDesigner::NodeTypeInfoTool.new }

      Registry.register(
        "mission_designer.apply_flow_patch",
        name: "Apply Flow Patch",
        description: "Apply a batch patch to the mission flow: add/update/remove nodes, edges, " \
                     "and globals in one call.",
        visible_in_headquarter: true,
        runtime_name: "apply_flow_patch",
        icon: "fa-solid fa-code-merge",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Applying the requested flow changes…",
            "Rewiring nodes and edges…",
            "Merging workflow updates…",
          ],
          complete_messages: [
            "Flow patch applied.",
            "Workflow changes committed.",
            "Canvas updated.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |agent: nil, parent_chat: nil, mission: nil, ui_context: nil, **|
        runtime_context = designer_runtime_context(agent:, parent_chat:, mission:, ui_context:)
        MissionDesigner::ApplyFlowPatchTool.new(mission, runtime_context:)
      end

      Registry.register(
        "mission_designer.add_node",
        name: "Add Node",
        description: "Create a new node in the mission workflow.",
        visible_in_headquarter: true,
        runtime_name: "add_node",
        icon: "fa-solid fa-plus",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Placing a new node on the canvas…",
            "Preparing the next node slot…",
            "Applying the requested node setup…",
          ],
          complete_messages: [
            "New node added to the flow.",
            "Canvas updated with the new node.",
            "Node creation completed.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        MissionDesigner::AddNodeTool.new(tool_context[:mission], runtime_context:)
      end

      Registry.register(
        "mission_designer.update_node",
        name: "Update Node",
        description: "Update a mission node configuration or label.",
        visible_in_headquarter: true,
        runtime_name: "update_node",
        icon: "fa-solid fa-pen",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Editing the node configuration…",
            "Rewriting node settings…",
            "Syncing the updated node state…",
          ],
          complete_messages: [
            "Node updated.",
            "Node changes applied.",
            "Node configuration saved.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        MissionDesigner::UpdateNodeTool.new(tool_context[:mission], runtime_context:)
      end

      Registry.register(
        "mission_designer.remove_node",
        name: "Remove Node",
        description: "Remove a mission node and any connected edges.",
        visible_in_headquarter: true,
        runtime_name: "remove_node",
        icon: "fa-solid fa-trash",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Removing the node and linked edges…",
            "Cleaning up graph references…",
            "Pruning the canvas state…",
          ],
          complete_messages: [
            "Node removed from the flow.",
            "Graph cleanup completed.",
            "Node deletion finished.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        MissionDesigner::RemoveNodeTool.new(tool_context[:mission], runtime_context:)
      end

      Registry.register(
        "mission_designer.manage_edges",
        name: "Manage Edges",
        description: "Add or remove edges between mission nodes.",
        visible_in_headquarter: true,
        runtime_name: "manage_edges",
        icon: "fa-solid fa-share-nodes",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Rewiring node connections…",
            "Applying edge changes…",
            "Reconciling graph links…",
          ],
          complete_messages: [
            "Edge changes applied.",
            "Connections updated.",
            "Graph wiring is now in sync.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        MissionDesigner::ManageEdgesTool.new(tool_context[:mission], runtime_context:)
      end

      Registry.register(
        "mission_designer.arrange_flow",
        name: "Arrange Flow",
        description: "Auto-layout the current mission workflow.",
        visible_in_headquarter: true,
        runtime_name: "arrange_flow",
        icon: "fa-solid fa-wand-magic-sparkles",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Rearranging the workflow layout…",
            "Calculating a cleaner graph shape…",
            "Settling node positions…",
          ],
          complete_messages: [
            "Flow layout refreshed.",
            "Nodes have been arranged.",
            "Canvas layout completed.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        MissionDesigner::ArrangeFlowTool.new(tool_context[:mission], runtime_context:)
      end

      Registry.register(
        "mission_designer.manage_global_variables",
        name: "Manage Global Variables",
        description: "Create, update, remove, and list mission global variables.",
        visible_in_headquarter: true,
        runtime_name: "manage_global_variables",
        icon: "fa-solid fa-sliders",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Updating workflow variables…",
            "Syncing global variable definitions…",
            "Refreshing mission-level state…",
          ],
          complete_messages: [
            "Global variables updated.",
            "Variable changes saved.",
            "Mission variables are now in sync.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        MissionDesigner::ManageGlobalVariablesTool.new(tool_context[:mission], runtime_context:)
      end

      Registry.register(
        "mission_designer.list_node_variables",
        name: "List Node Variables",
        description: "Show exact variable names and types available at a mission node for downstream " \
                     "config, output selection, assertions, and shape checks. Use this when validation " \
                     "reports an unknown variable instead of guessing alternate names.",
        visible_in_headquarter: true,
        runtime_name: "list_node_variables",
        icon: "fa-solid fa-list-check",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: node_catalog_presentation,
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        MissionDesigner::ListNodeVariablesTool.new(tool_context[:mission], runtime_context:)
      end

      Registry.register(
        "mission_designer.validate_flow",
        name: "Validate Flow",
        description: "Validate the full mission workflow and report configuration issues.",
        visible_in_headquarter: true,
        runtime_name: "validate_flow",
        icon: "fa-solid fa-circle-check",
        compaction_policy: :replace_by_time,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Validating the workflow…",
            "Checking node configuration…",
            "Scanning for broken paths…",
          ],
          complete_messages: [
            "Workflow validation completed.",
            "Flow checks finished.",
            "Validation report is ready.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |agent: nil, parent_chat: nil, mission: nil, ui_context: nil, **|
        runtime_context = designer_runtime_context(agent:, parent_chat:, mission:, ui_context:)
        MissionDesigner::ValidateFlowTool.new(mission, runtime_context:)
      end

      Registry.register(
        "mission_designer.run_debug",
        name: "Run Mission Debug",
        description: "Run the mission in debug mode with an explicit user-requested input payload " \
                     "and persist a MissionRun.",
        visible_in_headquarter: true,
        runtime_name: "run_mission_debug",
        icon: "fa-solid fa-play",
        compaction_policy: :replace_by_time,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Running the mission in debug mode…",
            "Executing the workflow against the provided payload…",
            "Collecting the latest run results…",
          ],
          complete_messages: [
            "Mission debug run finished.",
            "Run results are ready.",
            "Debug execution completed.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |agent: nil, parent_chat: nil, mission: nil, ui_context: nil, **|
        runtime_context = designer_runtime_context(agent:, parent_chat:, mission:, ui_context:)
        MissionDesigner::RunDebugTool.new(mission, runtime_context:)
      end

      Registry.register(
        "mission_designer.read_run",
        name: "Read Mission Run",
        description: "Read one mission run or list recent runs for the current mission.",
        visible_in_headquarter: true,
        runtime_name: "read_mission_run",
        icon: "fa-solid fa-timeline",
        compaction_policy: :replace_by_time,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading mission run data…",
            "Collecting the latest run records…",
            "Loading execution details from mission history…",
          ],
          complete_messages: [
            "Mission run data loaded.",
            "Execution history is ready.",
            "Run details collected.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) do |agent: nil, parent_chat: nil, mission: nil, ui_context: nil, **|
        runtime_context = designer_runtime_context(agent:, parent_chat:, mission:, ui_context:)
        MissionDesigner::ReadRunTool.new(mission, runtime_context:)
      end

      Registry.register(
        "mission_designer.expression_reference",
        name: "Expression Reference",
        description: "Return the full mission expression/formula reference.",
        visible_in_headquarter: true,
        runtime_name: "get_expression_reference",
        icon: "fa-solid fa-book",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Pulling up the expression reference…",
            "Loading formula syntax docs…",
            "Fetching operator and function list…",
          ],
          complete_messages: [
            "Expression reference ready.",
            "Formula docs loaded.",
          ],
          group_title: MISSION_DESIGNER_GROUP_TITLE,
        ),
      ) { |**| MissionDesigner::ExpressionReferenceTool.new }
    end

    def register_agent_designer_tools
      Registry.register(
        "agent_designer.read_agent",
        name: "Read Agent",
        description: "Inspect the current agent configuration and editable fields.",
        visible_in_headquarter: true,
        runtime_name: "read_agent",
        icon: "fa-solid fa-user-gear",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current agent configuration…",
            "Collecting agent settings and assignments…",
            "Inspecting the latest agent state…",
          ],
          complete_messages: [
            "Agent configuration loaded.",
            "Agent state is ready.",
            "Current agent details captured.",
          ],
          group_title: AGENT_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        AgentDesigner::ReadAgentTool.new(runtime_context:, current_agent: tool_context[:current_agent])
      end

      Registry.register(
        "agent_designer.read_agent_chat",
        name: "Read Agent Chat",
        description: "Inspect recent chats or one specific chat for the current agent with inspector-style details.",
        visible_in_headquarter: true,
        runtime_name: "read_agent_chat",
        icon: "fa-solid fa-comments",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Opening the latest agent chats…",
            "Inspecting the agent transcript…",
            "Loading agent chat diagnostics…",
          ],
          complete_messages: [
            "Agent chat history loaded.",
            "Agent transcript is ready.",
            "Agent chat diagnostics captured.",
          ],
          group_title: AGENT_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        AgentDesigner::ReadAgentChatTool.new(runtime_context:, current_agent: tool_context[:current_agent])
      end

      Registry.register(
        "agent_designer.debug_agent",
        name: "Debug Agent",
        description: "Send a synchronous debug prompt to an agent and persist the resulting chat for inspection.",
        visible_in_headquarter: true,
        runtime_name: "debug_agent",
        icon: "fa-solid fa-stethoscope",
        compaction_policy: :replace_by_args,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Sending the debug prompt to the agent…",
            "Waiting for the agent response…",
            "Running the agent debug chat…",
          ],
          complete_messages: [
            "Agent debug chat completed.",
            "Agent response captured.",
            "Debug transcript is ready.",
          ],
          group_title: AGENT_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        AgentDesigner::DebugAgentTool.new(runtime_context:, current_agent: tool_context[:current_agent])
      end

      Registry.register(
        "agent_designer.manage_capability",
        name: "Manage Capability",
        description: "Enable, update, or remove an agent capability using the capability plugin schema.",
        visible_in_headquarter: true,
        runtime_name: "manage_capability",
        icon: "fa-solid fa-bolt",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Applying the capability change…",
            "Validating the capability configuration…",
            "Updating the agent capability state…",
          ],
          complete_messages: [
            "Capability change applied.",
            "Capability configuration saved.",
            "Agent capability state updated.",
          ],
          group_title: AGENT_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        AgentDesigner::ManageCapabilityTool.new(runtime_context:, current_agent: tool_context[:current_agent])
      end

      Registry.register(
        "agent_designer.manage_agent_action",
        name: "Manage Agent Action",
        description: "Run agent admin actions that are not covered by generic CRUD, such as restoring built-ins.",
        visible_in_headquarter: true,
        runtime_name: "manage_agent_action",
        icon: "fa-solid fa-rotate-left",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Running the requested agent action…",
            "Applying the built-in agent workflow…",
            "Saving the agent-side admin action…",
          ],
          complete_messages: [
            "Agent action completed.",
            "Built-in agent workflow finished.",
            "Agent admin action applied.",
          ],
          group_title: AGENT_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        AgentDesigner::ManageAgentActionTool.new(runtime_context:, current_agent: tool_context[:current_agent])
      end
    end

    def register_channel_designer_tools
      Registry.register(
        "channel_designer.read_channel",
        name: "Read Channel",
        description: "Inspect the current channel configuration, labels, targets, and editable fields.",
        visible_in_headquarter: true,
        runtime_name: "read_channel",
        icon: "fa-solid fa-tower-broadcast",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current channel configuration…",
            "Collecting channel routing and copy…",
            "Inspecting the latest channel state…",
          ],
          complete_messages: [
            "Channel configuration loaded.",
            "Channel state is ready.",
            "Current channel details captured.",
          ],
          group_title: CHANNEL_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        ChannelDesigner::ReadChannelTool.new(runtime_context:, current_channel: tool_context[:current_channel])
      end

      Registry.register(
        "channel_designer.manage_channel_action",
        name: "Manage Channel Action",
        description:
          "Run channel admin actions that are not covered by generic CRUD, such as token rotation or webhook setup.",
        visible_in_headquarter: true,
        runtime_name: "manage_channel_action",
        icon: "fa-solid fa-rotate",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Running the requested channel action…",
            "Applying the channel-side admin workflow…",
            "Saving the channel action…",
          ],
          complete_messages: [
            "Channel action completed.",
            "Channel workflow finished.",
            "Channel admin action applied.",
          ],
          group_title: CHANNEL_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        ChannelDesigner::ManageChannelActionTool.new(runtime_context:, current_channel: tool_context[:current_channel])
      end
    end

    def register_skill_catalog_designer_tools
      Registry.register(
        "skill_catalog_designer.read_skill_catalog",
        name: "Read Skill Catalog",
        description: "Inspect the current skill catalog, its skills, assignments, and editable fields.",
        visible_in_headquarter: true,
        runtime_name: "read_skill_catalog",
        icon: "fa-solid fa-book-open",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current skill catalog…",
            "Collecting skill catalog details and assignments…",
            "Inspecting the latest skill catalog state…",
          ],
          complete_messages: [
            "Skill catalog loaded.",
            "Skill catalog details are ready.",
            "Current skill catalog state captured.",
          ],
          group_title: SKILL_CATALOG_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        SkillCatalogDesigner::ReadSkillCatalogTool.new(runtime_context:)
      end

      Registry.register(
        "skill_catalog_designer.read_skill",
        name: "Read Skill",
        description: "Inspect the current skill, its metadata, resources, and editable fields.",
        visible_in_headquarter: true,
        runtime_name: "read_skill",
        icon: "fa-solid fa-file-lines",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current skill…",
            "Collecting skill metadata and resources…",
            "Inspecting the latest skill state…",
          ],
          complete_messages: [
            "Skill details loaded.",
            "Skill metadata is ready.",
            "Current skill state captured.",
          ],
          group_title: SKILL_CATALOG_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        SkillCatalogDesigner::ReadSkillTool.new(runtime_context:)
      end

      Registry.register(
        "skill_catalog_designer.manage_skill",
        name: "Manage Skill",
        description: "Create, update, delete, restore, or import a skill inside the current skill catalog.",
        visible_in_headquarter: true,
        runtime_name: "manage_skill",
        icon: "fa-solid fa-wand-magic-sparkles",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Applying the skill change…",
            "Saving the skill and its resources…",
            "Running the requested skill workflow…",
          ],
          complete_messages: [
            "Skill change applied.",
            "Skill workflow finished.",
            "Skill state updated.",
          ],
          group_title: SKILL_CATALOG_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        SkillCatalogDesigner::ManageSkillTool.new(runtime_context:)
      end

      Registry.register(
        "skill_catalog_designer.manage_skill_catalog_action",
        name: "Manage Skill Catalog Action",
        description: "Run skill catalog admin actions such as import, restore, and agent assignment.",
        visible_in_headquarter: true,
        runtime_name: "manage_skill_catalog_action",
        icon: "fa-solid fa-box-open",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Running the requested skill catalog action…",
            "Applying the catalog-side admin workflow…",
            "Saving the skill catalog action…",
          ],
          complete_messages: [
            "Skill catalog action completed.",
            "Skill catalog workflow finished.",
            "Skill catalog state updated.",
          ],
          group_title: SKILL_CATALOG_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        SkillCatalogDesigner::ManageSkillCatalogActionTool.new(runtime_context:)
      end
    end

    def register_test_suite_designer_tools
      Registry.register(
        "test_suite_designer.read_test_suite",
        name: "Read Test Suite",
        description: "Inspect the current test suite, its test cases, latest run, and editable fields.",
        visible_in_headquarter: true,
        runtime_name: "read_test_suite",
        icon: "fa-solid fa-flask-vial",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current test suite…",
            "Collecting test cases and latest run data…",
            "Inspecting the latest test suite state…",
          ],
          complete_messages: [
            "Test suite loaded.",
            "Test suite details are ready.",
            "Current test suite state captured.",
          ],
          group_title: TEST_SUITE_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        TestSuiteDesigner::ReadTestSuiteTool.new(
          runtime_context:,
          current_test_suite: tool_context[:current_test_suite],
        )
      end

      Registry.register(
        "test_suite_designer.manage_test_case",
        name: "Manage Test Case",
        description: "Create, update, or delete a test case inside the current test suite.",
        visible_in_headquarter: true,
        runtime_name: "manage_test_case",
        icon: "fa-solid fa-vial",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Applying the test change…",
            "Saving the requested test case update…",
            "Updating the nested test case state…",
          ],
          complete_messages: [
            "Test case change applied.",
            "Nested test case saved.",
            "Test case state updated.",
          ],
          group_title: TEST_SUITE_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        TestSuiteDesigner::ManageTestCaseTool.new(
          runtime_context:,
          current_test_suite: tool_context[:current_test_suite],
        )
      end

      Registry.register(
        "test_suite_designer.manage_test_suite_action",
        name: "Manage Test Suite Action",
        description: "Run a full test suite or a single test synchronously and return the latest result summary.",
        visible_in_headquarter: true,
        runtime_name: "manage_test_suite_action",
        icon: "fa-solid fa-play",
        compaction_policy: :replace_by_time,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Running the requested tests…",
            "Executing the test suite synchronously…",
            "Collecting the latest run summary…",
          ],
          complete_messages: [
            "Test run finished.",
            "Latest run summary is ready.",
            "Test suite action completed.",
          ],
          group_title: TEST_SUITE_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        TestSuiteDesigner::ManageTestSuiteActionTool.new(
          runtime_context:,
          current_test_suite: tool_context[:current_test_suite],
        )
      end

      Registry.register(
        "test_suite_designer.read_test_suite_run",
        name: "Read Test Suite Run",
        description: "Read one test suite run or list recent runs for the current test suite.",
        visible_in_headquarter: true,
        runtime_name: "read_test_suite_run",
        icon: "fa-solid fa-timeline",
        compaction_policy: :replace_by_time,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading test run data…",
            "Collecting the latest suite execution details…",
            "Loading run history from the selected suite…",
          ],
          complete_messages: [
            "Test run data loaded.",
            "Suite execution history is ready.",
            "Run details collected.",
          ],
          group_title: TEST_SUITE_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        TestSuiteDesigner::ReadTestSuiteRunTool.new(
          runtime_context:,
          current_test_suite: tool_context[:current_test_suite],
        )
      end
    end

    def register_client_designer_tools
      Registry.register(
        "client_designer.read_client",
        name: "Read Client",
        description: "Inspect the current client configuration, labels, content, and editable fields.",
        visible_in_headquarter: true,
        runtime_name: "read_client",
        icon: "fa-solid fa-users-gear",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current client configuration…",
            "Collecting client copy, labels, and assignments…",
            "Inspecting the latest client-facing settings…",
          ],
          complete_messages: [
            "Client configuration loaded.",
            "Client-facing settings are ready.",
            "Current client details captured.",
          ],
          group_title: CLIENT_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        ClientDesigner::ReadClientTool.new(runtime_context:, current_client: tool_context[:current_client])
      end
    end

    def register_tool_designer_tools
      Registry.register(
        "tool_designer.read_tool",
        name: "Read Tool",
        description: "Inspect the current tool configuration, assignments, and supported actions.",
        visible_in_headquarter: true,
        runtime_name: "read_tool",
        icon: "fa-solid fa-screwdriver-wrench",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading the current tool configuration…",
            "Collecting tool settings and assignments…",
            "Inspecting the latest tool state…",
          ],
          complete_messages: [
            "Tool configuration loaded.",
            "Tool state is ready.",
            "Current tool details captured.",
          ],
          group_title: TOOL_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        ToolDesigner::ReadToolTool.new(runtime_context:, current_tool: tool_context[:current_tool])
      end

      Registry.register(
        "tool_designer.tool_type_info",
        name: "Tool Type Info",
        description: "Show the editable configuration fields, plugin notes, and supported actions for a tool type.",
        visible_in_headquarter: true,
        runtime_name: "get_tool_type_info",
        icon: "fa-solid fa-circle-info",
        compaction_policy: :replace_on_assistant_reply,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Looking up tool type guidance…",
            "Gathering tool configuration details…",
            "Opening the tool setup playbook…",
          ],
          complete_messages: [
            "Tool type guidance is ready.",
            "Tool configuration details collected.",
            "Tool type info loaded.",
          ],
          group_title: TOOL_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        ToolDesigner::ToolTypeInfoTool.new(current_tool: tool_context[:current_tool])
      end

      Registry.register(
        "tool_designer.manage_tool_action",
        name: "Manage Tool Action",
        description: "Run an existing tool-specific admin action such as discovery or visibility updates.",
        visible_in_headquarter: true,
        runtime_name: "manage_tool_action",
        icon: "fa-solid fa-play",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Running the requested tool action…",
            "Calling the existing tool workflow…",
            "Applying the tool-side admin action…",
          ],
          complete_messages: [
            "Tool action completed.",
            "Tool workflow finished.",
            "Tool admin action applied.",
          ],
          group_title: TOOL_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        ToolDesigner::ManageToolActionTool.new(runtime_context:, current_tool: tool_context[:current_tool])
      end
    end

    def register_cost_designer_tools
      Registry.register(
        "cost_designer.read_cost_analysis",
        name: "Read Cost Analysis",
        description: "Read cost dashboard summaries, spend breakdowns, and active limit health.",
        visible_in_headquarter: true,
        runtime_name: "read_cost_analysis",
        icon: "fa-solid fa-chart-line",
        compaction_policy: :replace_by_time,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading cost analysis data…",
            "Aggregating spend and token usage…",
            "Checking active cost limits…",
          ],
          complete_messages: [
            "Cost analysis loaded.",
            "Spend breakdown is ready.",
            "Limit health collected.",
          ],
          group_title: COST_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        CostDesigner::ReadCostAnalysisTool.new(runtime_context:)
      end

      Registry.register(
        "cost_designer.read_cost_limit",
        name: "Read Cost Limit",
        description: "Read a cost limit or list all limits with current spend status.",
        visible_in_headquarter: true,
        runtime_name: "read_cost_limit",
        icon: "fa-solid fa-gauge-high",
        compaction_policy: :replace_by_args,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Reading cost limit status…",
            "Calculating budget usage…",
            "Loading cost guardrail details…",
          ],
          complete_messages: [
            "Cost limit status loaded.",
            "Budget usage is ready.",
            "Cost guardrail details collected.",
          ],
          group_title: COST_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        CostDesigner::ReadCostLimitTool.new(runtime_context:)
      end

      Registry.register(
        "cost_designer.manage_cost_limit",
        name: "Manage Cost Limit",
        description: "Create, update, delete, or toggle cost limits in the current tenant.",
        visible_in_headquarter: true,
        runtime_name: "manage_cost_limit",
        icon: "fa-solid fa-sliders",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Applying the cost limit change…",
            "Validating the budget guardrail…",
            "Saving cost control settings…",
          ],
          complete_messages: [
            "Cost limit change applied.",
            "Budget guardrail saved.",
            "Cost control settings updated.",
          ],
          group_title: COST_DESIGNER_GROUP_TITLE,
        ),
      ) do |**tool_context|
        runtime_context = designer_runtime_context_from(tool_context)
        CostDesigner::ManageCostLimitTool.new(runtime_context:)
      end
    end

    def designer_runtime_context_from(tool_context)
      designer_runtime_context(
        agent: tool_context[:agent],
        parent_chat: tool_context[:parent_chat],
        mission: tool_context[:mission],
        ui_context: tool_context[:ui_context],
      )
    end

    def register_record_admin_tools
      Registry.register(
        "records.manage_record",
        name: "Manage Record",
        description: "Create, update, or delete a supported admin record within the current tenant and operation.",
        visible_in_headquarter: true,
        runtime_name: "manage_record",
        icon: "fa-solid fa-pen-to-square",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Applying the record change...",
            "Saving the requested admin update...",
            "Committing the record mutation...",
          ],
          complete_messages: [
            "Record change applied.",
            "Admin update completed.",
            "Record mutation finished.",
          ],
          group_title: ADMIN_RECORDS_GROUP_TITLE,
        ),
      ) do |agent: nil, parent_chat: nil, mission: nil, ui_context: nil, **|
        ManageRecordTool.new(agent:, parent_chat:, mission:, ui_context:)
      end

      Registry.register(
        "navigation.navigate_to_page",
        name: "Navigate To Page",
        description: "Point the admin UI to a supported page after a record change. " \
                     "This tool does not read page content or return record information.",
        visible_in_headquarter: true,
        runtime_name: "navigate_to_page",
        icon: "fa-solid fa-arrow-right",
        compaction_policy: :drop_all,
        tool_call_presentation: tool_call_presentation(
          running_messages: [
            "Resolving the next page...",
            "Preparing the Turbo navigation...",
            "Moving the admin UI...",
          ],
          complete_messages: [
            "Page navigation prepared.",
            "Turbo navigation completed.",
            "UI move finished.",
          ],
          group_title: ADMIN_RECORDS_GROUP_TITLE,
        ),
      ) do |agent: nil, parent_chat: nil, mission: nil, ui_context: nil, **|
        NavigateToPageTool.new(agent:, parent_chat:, mission:, ui_context:)
      end
    end

    def register_plugin_builtin_tools
      ToolPlugin.all_types.each do |type|
        tool_class = ToolPlugin.resolve(type.fetch(:key))
        next unless tool_class

        tool_class.register_builtin_tools(self)
      rescue NameError
        next
      end
    end
  end
end

# rubocop:enable Metrics/MethodLength, Metrics/ModuleLength, Metrics/AbcSize
