# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
# rubocop:disable RSpec/ExampleLength
# rubocop:disable RSpec/MultipleExpectations

require "rails_helper"

RSpec.describe "Tool branch coverage backfill" do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:skill_catalog) { create(:skill_catalog, operation:, name: "Coverage Catalog") }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def runtime_context(
    tenant_override: tenant,
    operation_override: operation,
    chat_override: chat,
    ui_path: "/admin/test",
    current_object: nil
  )
    ui_context = if current_object
                   {
                     "current_object" => current_object,
                     "page" => { "path" => ui_path },
                   }
                 else
                   { "page" => { "path" => ui_path } }
                 end
    ui_context = nil if ui_path.nil? && current_object.nil?

    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: chat_override,
      mission: nil,
      ui_context:,
      user:,
      tenant: tenant_override,
      operation: operation_override,
    )
  end

  def attach_chat_file(target_chat, filename, content = "content")
    message = target_chat.messages.create!(role: :user, content: "Use the attachment")
    message.attachments.attach(io: StringIO.new(content), filename:, content_type: "text/markdown")
    message.reload
  end

  def build_support_host(mod, methods = {})
    klass = Class.new do
      include mod

      def initialize(runtime_context:, current_skill: nil, current_skill_catalog: nil)
        @runtime_context = runtime_context
        @current_skill = current_skill
        @current_skill_catalog = current_skill_catalog
      end

      attr_reader :current_skill
    end

    methods.each do |name, impl|
      klass.define_method(name, &impl)
    end

    klass
  end

  it "covers negative current-page refresh branches" do
    host_class = Class.new do
      include CurrentPageRefreshable

      def initialize(runtime_context)
        @runtime_context = runtime_context
      end
    end

    expect(host_class.new(nil).send(:broadcast_current_page_refresh?)).to be(false)

    non_app_chat = instance_double(Chat, application?: false, user_id: user.id)
    expect(host_class.new(runtime_context(chat_override: non_app_chat)).send(:refreshable_chat)).to be_nil

    anonymous_chat = instance_double(Chat, application?: true, user_id: nil)
    expect(host_class.new(runtime_context(chat_override: anonymous_chat)).send(:refreshable_chat)).to be_nil

    no_path_host = host_class.new(runtime_context(ui_path: nil))
    expect(no_path_host.send(:current_page_path)).to be_nil
    expect(no_path_host.send(:broadcast_current_page_refresh?)).to be(false)
  end

  it "covers attachment helper fallback branches" do
    host_class = Class.new do
      include SkillCatalogDesigner::AttachmentSupport

      def initialize(runtime_context)
        @runtime_context = runtime_context
      end
    end

    nil_host = host_class.new(nil)
    expect(nil_host.send(:latest_user_attachments)).to eq([])

    empty_chat = create(:chat, :application_context, user:)
    empty_host = host_class.new(runtime_context(chat_override: empty_chat))
    expect(empty_host.send(:latest_user_attachments)).to eq([])
    expect(empty_host.send(:with_selected_upload, nil)).to include("No file attachment")

    single_chat = create(:chat, :application_context, user:)
    attach_chat_file(single_chat, "only.md")
    single_host = host_class.new(runtime_context(chat_override: single_chat))
    attachment, error = single_host.send(:resolve_single_attachment, nil)
    expect(attachment.blob.filename.to_s).to eq("only.md")
    expect(error).to be_nil
  end

  it "covers skill lookup fallback branches and optional read-skill summary lines" do
    lookup_host_class = Class.new do
      include SkillCatalogDesigner::SkillLookup

      def initialize(runtime_context:, current_skill: nil)
        @runtime_context = runtime_context
        @current_skill = current_skill
      end
    end

    default_host = lookup_host_class.new(runtime_context: nil)
    expect(default_host.send(:current_skill)).to be_nil
    expect(default_host.send(:operation)).to be_nil
    Current.set(tenant:) do
      tenant_host = lookup_host_class.new(
        runtime_context: runtime_context(
          tenant_override: nil,
          operation_override: nil,
        ),
      )
      expect(tenant_host.send(:skill_scope).to_sql).to include("operations")
      expect(tenant_host.send(:tenant)).to eq(tenant)
    end
    no_scope_host = Class.new do
      include SkillCatalogDesigner::SkillLookup

      def tenant
        nil
      end

      def operation
        nil
      end
    end.new
    expect(no_scope_host.send(:skill_scope).to_sql).not_to include("operations")

    current_skill = create(:skill, skill_catalog:, name: "lookup-skill")
    current_skill_host = lookup_host_class.new(runtime_context: nil, current_skill:)
    expect(current_skill_host.send(:tenant)).to eq(tenant)
    expect(
      SkillCatalogDesigner::ReadSkillCatalogTool.new(runtime_context:)
                                              .send(:current_skill_catalog_from_skill_object, { "id" => "missing" }),
    ).to be_nil

    skill = create(
      :skill,
      :builtin,
      skill_catalog: create(:skill_catalog, :builtin, operation: tenant.headquarter_operation),
      license: "MIT",
      compatibility: "Ruby 4",
      allowed_tools: "read_skill,manage_skill",
    )
    result = SkillCatalogDesigner::ReadSkillTool.new(runtime_context:, current_skill: skill).execute
    expect(result).to include("Built-in key")
    expect(result).to include("License: MIT")
    expect(result).to include("Compatibility: Ruby 4")
    expect(result).to include("Allowed tools: read_skill,manage_skill")
  end

  it "covers manage_skill tool and support branch fallbacks" do
    blank_context = runtime_context(tenant_override: nil, operation_override: nil, ui_path: nil)
    create_tool = SkillCatalogDesigner::ManageSkillTool.new(runtime_context: blank_context)
    expect(create_tool.execute(action: "create")).to include("No current skill catalog is available")
    blank_create_tool = SkillCatalogDesigner::ManageSkillTool.new(
      runtime_context: blank_context,
      current_skill_catalog: skill_catalog,
    )
    expect(blank_create_tool.execute(action: "create")).to eq("Error: Provide attributes for create.")

    current_skill = create(:skill, skill_catalog:, name: "branch-skill")
    update_tool = SkillCatalogDesigner::ManageSkillTool.new(
      runtime_context: blank_context,
      current_skill:,
    )
    expect(update_tool.execute(action: "update")).to eq("Error: Provide attributes for update.")
    expect(create_tool.execute(action: "update")).to include("No current skill is available")
    expect(create_tool.execute(action: "delete")).to include("No current skill is available")
    expect(update_tool.execute(action: "delete", confirm_destroy: false))
      .to eq("Error: confirm_destroy must be true for delete actions.")

    delete_result = update_tool.execute(action: "delete", confirm_destroy: true)
    expect(delete_result).to include("Skill deleted successfully.")
    expect(delete_result).not_to include("Current page refresh")

    builtin_catalog = create(
      :skill_catalog,
      :builtin,
      operation: tenant.headquarter_operation,
      source_metadata: { "builtin_key" => "coverage-catalog" },
    )
    builtin_skill = create(
      :skill,
      :builtin,
      skill_catalog: builtin_catalog,
      source_metadata: { "builtin_key" => "coverage-skill" },
    )
    restore_tool = SkillCatalogDesigner::ManageSkillTool.new(
      runtime_context: runtime_context(operation_override: tenant.headquarter_operation, ui_path: nil),
      current_skill: builtin_skill,
    )
    allow(BuiltinSkills::Synchronizer).to receive(:restore!).with("coverage-catalog", tenant:)
    expect(restore_tool.execute(action: "restore")).not_to include("Current page refresh")
    expect(create_tool.execute(action: "restore")).to include("No current skill is available")

    import_chat = create(:chat, :application_context, user:)
    attach_chat_file(import_chat, "skill.md", <<~MARKDOWN)
      ---
      name: imported-skill
      description: imported
      ---
    MARKDOWN
    imported_skill = create(:skill, skill_catalog:, name: "imported-skill")
    import_result = double(skills: [imported_skill], warnings: ["warning"])
    import_tool = SkillCatalogDesigner::ManageSkillTool.new(
      runtime_context: runtime_context(chat_override: import_chat, ui_path: nil),
      current_skill_catalog: skill_catalog,
    )
    allow(Skills::ImportService).to receive(:new).and_return(double(call: import_result))
    expect(create_tool.execute(action: "import")).to include("No current skill catalog is available")
    result = import_tool.execute(action: "import")
    expect(result).to include("- Warnings: 1")
    expect(result).not_to include("Current page refresh")

    support_host_class = build_support_host(SkillCatalogDesigner::ManageSkillSupport)
    support_host = support_host_class.new(runtime_context: nil, current_skill: nil, current_skill_catalog: nil)
    expect { support_host.send(:normalize_attributes, { "unknown" => true }) }
      .to raise_error(ArgumentError, /Unknown skill attributes/)
    expect(support_host.send(:normalized_metadata, " ")).to eq({})
    expect(support_host.send(:success_message, skill: imported_skill, action: "update", refreshed: false))
      .not_to include("Current page refresh")
    expect(support_host.send(:tenant)).to eq(Tenant.default_tenant)

    current_skill_host = support_host_class.new(
      runtime_context: nil,
      current_skill:,
      current_skill_catalog: nil,
    )
    expect(current_skill_host.send(:tenant)).to eq(tenant)

    nil_skill_host = support_host_class.new(
      runtime_context: nil,
      current_skill: double(skill_catalog: nil),
      current_skill_catalog: double(operation: nil),
    )
    expect(nil_skill_host.send(:current_skill_operation)).to be_nil
    expect(nil_skill_host.send(:current_skill_catalog_tenant)).to be_nil

    resource_skill = create(:skill, skill_catalog:, name: "resource-skill")
    removable = create(:skill_resource, skill: resource_skill)
    update_tool.send(
      :apply_resource_updates,
      resource_skill,
      { "remove_resource_ids" => [removable.id], "use_current_message_attachments" => false },
    )
    expect(resource_skill.skill_resources.find_by(id: removable.id)).to be_nil
  end

  it "covers manage_skill_catalog_action tool and support branch fallbacks" do
    blank_context = runtime_context(tenant_override: nil, operation_override: nil, ui_path: nil)
    tool = SkillCatalogDesigner::ManageSkillCatalogActionTool.new(runtime_context: blank_context)
    expect(tool.execute(action: "restore")).to include("No current skill catalog is available")
    expect(tool.execute(action: "attach_agent")).to include("No current skill catalog is available")
    expect(tool.execute(action: "detach_agent")).to include("No current skill catalog is available")
    expect(tool.execute(action: "import")).to include("No current skill catalog is available")

    scoped_tool = SkillCatalogDesigner::ManageSkillCatalogActionTool.new(
      runtime_context: blank_context,
      current_skill_catalog: skill_catalog,
    )
    expect(scoped_tool.execute(action: "attach_agent")).to include("Provide agent_id for attach_agent")

    non_builtin_restore = scoped_tool.execute(action: "restore")
    expect(non_builtin_restore).to include("not a built-in skill catalog")

    invalid_record = build(:agent)
    invalid_record.errors.add(:base, "Invalid state")
    allow(scoped_tool).to receive(:detach_agent).and_raise(ActiveRecord::RecordInvalid.new(invalid_record))
    expect(scoped_tool.execute(action: "detach_agent", agent_id: "missing")).to include("Invalid state")

    defaults_result = double(restored_keys: ["a"], created_keys: [])
    allow(BuiltinSkills::Synchronizer).to receive(:restore_all!).and_return(defaults_result)
    expect(scoped_tool.execute(action: "restore_defaults")).not_to include("Current page refresh")
    allow(scoped_tool).to receive(:authorize_policy!)
    expect(scoped_tool.send(:restore_defaults)).not_to include("Current page refresh")

    import_chat = create(:chat, :application_context, user:)
    attach_chat_file(import_chat, "collection.zip", "zip")
    imported_skill = create(:skill, skill_catalog:, name: "collection-skill")
    import_result = double(skills: [imported_skill], warnings: ["warning"])
    import_tool = SkillCatalogDesigner::ManageSkillCatalogActionTool.new(
      runtime_context: runtime_context(chat_override: import_chat, ui_path: nil),
      current_skill_catalog: skill_catalog,
    )
    allow(Skills::ImportService).to receive(:new).and_return(double(call: import_result))
    import_message = import_tool.execute(action: "import_collection")
    expect(import_message).to include("- Warnings: 1")
    expect(import_message).not_to include("Current page refresh")

    support_host_class = Class.new do
      include SkillCatalogDesigner::ManageSkillCatalogActionSupport

      def initialize(runtime_context:, current_skill_catalog: nil)
        @runtime_context = runtime_context
        @current_skill_catalog = current_skill_catalog
      end
    end
    support_host = support_host_class.new(runtime_context: nil)
    expect(support_host.send(:catalog_action_message, skill_catalog:, action: "noop", refreshed: false))
      .not_to include("Current page refresh")
    expect(support_host.send(:tenant)).to eq(Tenant.default_tenant)
    expect(support_host.send(:operation)).to eq(Tenant.default_tenant.default_operation)
  end

  it "covers agent and channel action fallback branches" do
    agent_tool = AgentDesigner::ManageAgentActionTool.new(
      runtime_context: runtime_context(ui_path: nil),
      current_agent: nil,
    )
    expect(agent_tool.execute(action: "unknown")).to include("Unknown action")
    expect(agent_tool.execute(action: "restore")).to include("No current agent is available")

    manual_agent = instance_double(Agent, name: "Manual Agent", builtin?: false, operation:)
    allow(agent_tool).to receive(:resolve_agent).and_return(manual_agent)
    allow(agent_tool).to receive(:authorize_policy!)
    expect(agent_tool.execute(action: "restore")).to include("not a built-in agent")

    restore_agent_tool = AgentDesigner::ManageAgentActionTool.new(
      runtime_context: runtime_context(operation_override: tenant.headquarter_operation, ui_path: nil),
    )
    builtin_agent = instance_double(
      Agent,
      id: 123,
      name: "Builtin Agent",
      builtin?: true,
      builtin_key: "agent-key",
      operation: tenant.headquarter_operation,
    )
    allow(restore_agent_tool).to receive(:resolve_agent).and_return(builtin_agent)
    allow(restore_agent_tool).to receive(:authorize_policy!)
    allow(Agent).to receive(:find_builtin_by_key).with("agent-key", tenant:).and_return(builtin_agent)
    allow(BuiltinAgents::Synchronizer).to receive(:restore!).with("agent-key", tenant:)
    expect(restore_agent_tool.execute(action: "restore")).not_to include("Current page refresh")

    restore_defaults_result = double(restored_keys: ["one"], created_keys: [])
    allow(BuiltinAgents::Synchronizer).to receive(:restore_all!).and_return(restore_defaults_result)
    expect(restore_agent_tool.execute(action: "restore_defaults")).not_to include("Current page refresh")

    stub_const("AgentDesigner::ManageAgentActionTool::ACTIONS", { "noop" => :noop })
    expect(agent_tool.execute(action: "noop")).to be_nil
    expect(AgentDesigner::ManageAgentActionTool.new(runtime_context: nil).send(:tenant)).to eq(Tenant.default_tenant)
    tenantless_tool = AgentDesigner::ManageAgentActionTool.new(
      runtime_context: runtime_context(tenant_override: nil, operation_override: nil, ui_path: nil),
      current_agent: double(operation: nil),
    )
    expect(tenantless_tool.send(:tenant)).to eq(Tenant.default_tenant)
    current_agent_tenant_tool = AgentDesigner::ManageAgentActionTool.new(
      runtime_context: runtime_context(tenant_override: nil, operation_override: nil, ui_path: nil),
      current_agent: double(operation:),
    )
    expect(current_agent_tenant_tool.send(:tenant)).to eq(tenant)

    channel_tool = ChannelDesigner::ManageChannelActionTool.new(runtime_context: runtime_context(ui_path: nil))
    expect(channel_tool.execute(action: "unknown")).to include("Unknown action")
    expect(channel_tool.execute(action: "regenerate_token")).to include("No current channel is available")

    api_channel = create(:channel, :api, tenant:, name: "API")
    regen_tool = ChannelDesigner::ManageChannelActionTool.new(
      runtime_context: runtime_context(ui_path: nil),
      current_channel: api_channel,
    )
    raw_token = "secret-token"
    credential = create(:channel_credential, channel: api_channel)
    allow(api_channel.channel_credentials).to receive(:first_or_create!).and_return(credential)
    allow(credential).to receive(:regenerate_token!).and_return(raw_token)
    expect(regen_tool.execute(action: "regenerate_token")).not_to include("Current page refresh")

    client_channel = create(:channel, :client, tenant:, name: "Client")
    client_tool = ChannelDesigner::ManageChannelActionTool.new(
      runtime_context:,
      current_channel: client_channel,
    )
    expect(client_tool.execute(action: "regenerate_token")).to include("does not use API bearer tokens")

    telegram_channel = create(:channel, :telegram, tenant:, name: "Telegram")
    webhook_tool = ChannelDesigner::ManageChannelActionTool.new(
      runtime_context: runtime_context(ui_path: nil),
      current_channel: telegram_channel,
    )
    failure = instance_double(ToolPlugin::Result, success?: false, message: "Webhook failed")
    success = instance_double(ToolPlugin::Result, success?: true, message: "Webhook ok")
    allow(Telegram::WebhookSetupService).to receive(:new).and_return(double(call: failure), double(call: success))
    expect(webhook_tool.execute(action: "setup_webhook")).to eq("Error: Webhook failed")
    expect(webhook_tool.execute(action: "setup_webhook")).not_to include("Current page refresh")

    stub_const("ChannelDesigner::ManageChannelActionTool::ACTIONS", { "noop" => :noop })
    expect(regen_tool.execute(action: "noop")).to be_nil
  end

  it "covers skill policy restore when the skill catalog is absent" do
    orphan_skill = build_stubbed(
      :skill,
      :builtin,
      skill_catalog: nil,
      source_metadata: { "builtin_key" => "orphan-skill" },
    )

    expect(SkillPolicy.new(user, orphan_skill)).not_to be_restore
  end
end

# rubocop:enable RSpec/MultipleExpectations
# rubocop:enable RSpec/ExampleLength
# rubocop:enable RSpec/DescribeClass
