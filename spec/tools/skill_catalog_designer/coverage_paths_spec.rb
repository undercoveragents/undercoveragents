# frozen_string_literal: true

require "rails_helper"

RSpec.shared_context "with skill designer coverage setup" do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:skill_catalog) { create(:skill_catalog, operation:, name: "Support Playbooks") }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def runtime_context(tenant_override: tenant, operation_override: operation, current_object: nil)
    ui_context = if current_object
                   {
                     "current_object" => current_object,
                     "page" => { "path" => "/admin/test" },
                   }
                 end

    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context:,
      user:,
      tenant: tenant_override,
      operation: operation_override,
    )
  end

  def attach_user_files(*files)
    message = chat.messages.create!(role: :user, content: "Use the attachments.")
    files.each do |filename, content|
      message.attachments.attach(io: StringIO.new(content), filename:, content_type: "text/markdown")
    end
    message.reload
  end

  def valid_skill_markdown(name)
    <<~MARKDOWN
      ---
      name: #{name}
      description: Use this skill when #{name.tr("-", " ")} guidance is needed.
      ---

      # #{name.titleize}
    MARKDOWN
  end
end

RSpec.describe SkillCatalogDesigner do
  describe SkillCatalogDesigner::ManageSkillTool do
    include_context "with skill designer coverage setup"

    def manage_skill_tool(current_skill: nil, current_skill_catalog: skill_catalog, tenant_override: tenant,
                          operation_override: operation, current_object: nil)
      described_class.new(
        runtime_context: runtime_context(
          tenant_override:,
          operation_override:,
          current_object:,
        ),
        current_skill:,
        current_skill_catalog:,
      )
    end

    it "covers the delete path" do
      deletable_skill = create(:skill, skill_catalog:, name: "delete-me")
      tool = manage_skill_tool(
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )

      expect(tool.execute(action: "delete", skill_id: deletable_skill.id, confirm_destroy: true))
        .to include("Skill deleted successfully.")
      expect(skill_catalog.skills.find_by(id: deletable_skill.id)).to be_nil
    end

    it "covers create validation failures" do
      tool = manage_skill_tool(
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )

      expect(tool.execute(action: "create", attributes: { description: "Missing name" }))
        .to include("Name can't be blank")
    end

    it "covers restore and unknown-action errors" do
      manual_skill = create(:skill, skill_catalog:, name: "manual-skill")
      tool = manage_skill_tool(
        current_skill: manual_skill,
        current_object: { "class_name" => "Skill", "id" => manual_skill.id },
      )

      expect(tool.execute(action: "restore")).to include("not a built-in skill")
      expect(tool.execute(action: "bogus")).to include("Unknown action 'bogus'")
    end

    it "covers unexpected manage_skill failures" do
      tool = manage_skill_tool
      allow(tool).to receive(:create_skill).and_raise(StandardError, "boom")

      expect(tool.execute(action: "create")).to eq("Error managing skill: boom")
    end

    it "covers attribute normalization branches" do
      tool = manage_skill_tool
      attribute_params = ActionController::Parameters.new(
        name: "triage",
        remove_resource_ids: ["123", ""],
      )

      expect(tool.send(:normalize_attributes, attribute_params))
        .to include("name" => "triage", "remove_resource_ids" => ["123"])
      expect(tool.send(:normalize_attributes, "{\"name\":\"triage\"}"))
        .to include("name" => "triage")
      expect(tool.send(:normalize_attributes, "")).to eq({})
      expect { tool.send(:normalize_attributes, "[]") }
        .to raise_error(ArgumentError, /Expected attributes/)
    end

    it "covers metadata and resource helper branches" do
      skill = create(:skill, skill_catalog:, name: "helper-skill")
      resource = create(:skill_resource, skill:)
      tool = manage_skill_tool(
        current_skill: skill,
        current_object: { "class_name" => "Skill", "id" => skill.id },
      )

      expect { tool.send(:normalized_metadata, "[]") }
        .to raise_error(ArgumentError, /Expected metadata/)
      tool.send(:remove_selected_resources, skill, [])
      tool.send(:remove_selected_resources, skill, [resource.id])
      expect(skill.skill_resources.find_by(id: resource.id)).to be_nil
      expect { tool.send(:add_current_message_attachments, skill, nil) }
        .to raise_error(ArgumentError, /No file attachment/)
    end

    it "covers parse_hash support branches directly" do
      support_host = Class.new do
        include SkillCatalogDesigner::ManageSkillSupport

        def initialize(runtime_context:)
          @runtime_context = runtime_context
        end

        def current_skill
          nil
        end
      end.new(runtime_context:)

      expect(support_host.send(:parse_hash, nil)).to eq({})
      expect { support_host.send(:parse_hash, 123) }
        .to raise_error(ArgumentError, /Expected attributes/)
    end

    it "covers normalized_metadata support branches directly" do
      support_host = Class.new do
        include SkillCatalogDesigner::ManageSkillSupport

        def initialize(runtime_context:)
          @runtime_context = runtime_context
        end

        def current_skill
          nil
        end
      end.new(runtime_context:)

      expect(support_host.send(:normalized_metadata, nil)).to eq({})
      expect(support_host.send(:normalized_metadata, ActionController::Parameters.new(topic: "support")))
        .to eq("topic" => "support")
      expect(support_host.send(:normalized_metadata, "{\"topic\":\"support\"}"))
        .to eq("topic" => "support")
      expect { support_host.send(:normalized_metadata, 123) }
        .to raise_error(ArgumentError, /Expected metadata/)
    end

    it "covers tenant fallbacks from the current skill catalog and skill" do
      skill = create(:skill, skill_catalog:, name: "tenant-skill")
      catalog_tool = manage_skill_tool(
        tenant_override: nil,
        operation_override: nil,
      )
      skill_tool = manage_skill_tool(
        current_skill: skill,
        current_skill_catalog: nil,
        tenant_override: nil,
        operation_override: nil,
      )

      expect(catalog_tool.send(:tenant)).to eq(tenant)
      expect(skill_tool.send(:current_skill_operation)).to eq(operation)
      expect(skill_tool.send(:tenant)).to eq(tenant)
    end

    it "covers tenant fallback from Current" do
      bare_context = runtime_context(tenant_override: nil, operation_override: nil)

      Current.set(tenant:) do
        expect(described_class.new(runtime_context: bare_context).send(:tenant)).to eq(tenant)
      end
    end

    it "covers support tenant accessors directly" do
      skill = create(:skill, skill_catalog:, name: "support-skill")
      support_host = Class.new do
        include SkillCatalogDesigner::ManageSkillSupport

        attr_reader :current_skill

        def initialize(runtime_context:, current_skill:, current_skill_catalog:)
          @runtime_context = runtime_context
          @current_skill = current_skill
          @current_skill_catalog = current_skill_catalog
        end
      end.new(
        runtime_context:,
        current_skill: skill,
        current_skill_catalog: skill_catalog,
      )

      expect(support_host.send(:tenant)).to eq(tenant)
      expect(support_host.send(:current_skill_operation)).to eq(operation)
      expect(support_host.send(:current_skill_catalog_tenant)).to eq(tenant)
    end
  end

  describe SkillCatalogDesigner::ManageSkillCatalogActionTool do
    include_context "with skill designer coverage setup"

    def catalog_action_tool(current_skill_catalog: skill_catalog, tenant_override: tenant,
                            operation_override: operation, current_object: nil)
      described_class.new(
        runtime_context: runtime_context(
          tenant_override:,
          operation_override:,
          current_object:,
        ),
        current_skill_catalog:,
      )
    end

    it "restores a builtin skill catalog" do
      builtin_catalog = create(
        :skill_catalog,
        :builtin,
        operation: tenant.headquarter_operation,
        name: "Builtin Guides",
        source_metadata: { "builtin_key" => "undercover-agents-skills" },
      )
      tool = catalog_action_tool(
        current_skill_catalog: builtin_catalog,
        operation_override: tenant.headquarter_operation,
        current_object: { "class_name" => "SkillCatalog", "id" => builtin_catalog.id },
      )
      allow(BuiltinSkills::Synchronizer).to receive(:restore!).with("undercover-agents-skills", tenant:)

      result = Current.set(operation: tenant.headquarter_operation, tenant:) do
        tool.execute(action: "restore")
      end

      expect(result).to include("Built-in skill catalog restored to the shipped defaults.")
    end

    it "detaches an agent from a skill catalog" do
      agent_record = create(:agent, operation:, name: "Support Agent", model_id: "gpt-4.1")
      agent_record.skill_catalog_ids = [skill_catalog.id]
      agent_record.save!
      tool = catalog_action_tool(
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )

      expect(tool.execute(action: "detach_agent", agent_id: agent_record.id))
        .to include("Action: `detach_agent`")
      expect(agent_record.reload.skill_catalog_ids).to be_empty
    end

    it "covers attachment selection branches" do
      attach_user_files(["one.md", valid_skill_markdown("one")], ["two.md", valid_skill_markdown("two")])
      tool = catalog_action_tool(
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )

      attachment, error = tool.send(:resolve_single_attachment, "one.md")
      expect(attachment.blob.filename.to_s).to eq("one.md")
      expect(error).to be_nil
      expect(tool.send(:resolve_single_attachment, "missing.md").last).to include("was not found")
      expect(tool.send(:resolve_single_attachment, nil).last).to include("Multiple attachments")
    end

    it "covers unknown catalog actions and argument errors" do
      tool = catalog_action_tool(
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )

      expect(tool.execute(action: "bogus")).to include("Unknown action 'bogus'")
      expect(tool.execute(action: "detach_agent")).to include("Provide agent_id for detach_agent")
    end

    it "covers non-builtin restore and record-invalid catalog actions" do
      tool = catalog_action_tool(
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )
      invalid_record = build(:agent)
      invalid_record.errors.add(:base, "Invalid state")

      expect(tool.execute(action: "restore")).to include("not a built-in skill catalog")
      allow(tool).to receive(:detach_agent).and_raise(ActiveRecord::RecordInvalid.new(invalid_record))
      expect(tool.execute(action: "detach_agent", agent_id: "missing"))
        .to include("Invalid state")
    end

    it "covers unexpected catalog action failures" do
      tool = catalog_action_tool
      allow(tool).to receive(:resolve_skill_catalog).and_raise(StandardError, "boom")

      expect(tool.execute(action: "restore")).to eq("Error managing skill catalog action: boom")
    end

    it "covers tenant and operation support fallbacks" do
      bare_context = runtime_context(tenant_override: nil, operation_override: nil)
      catalog_tool = catalog_action_tool(
        tenant_override: nil,
        operation_override: nil,
      )

      expect(catalog_action_tool.send(:tenant)).to eq(tenant)
      expect(catalog_tool.send(:tenant)).to eq(tenant)
      expect(described_class.new(runtime_context: bare_context).send(:tenant)).to eq(Tenant.default_tenant)
      expect(catalog_tool.send(:operation)).to eq(operation)
    end

    it "covers catalog action support accessors directly" do
      support_host_class = Class.new do
        include SkillCatalogDesigner::ManageSkillCatalogActionSupport

        def initialize(runtime_context:, current_skill_catalog: nil)
          @runtime_context = runtime_context
          @current_skill_catalog = current_skill_catalog
        end
      end

      runtime_host = support_host_class.new(runtime_context:)
      catalog_host = support_host_class.new(
        runtime_context: runtime_context(tenant_override: nil, operation_override: nil),
        current_skill_catalog: skill_catalog,
      )
      default_host = support_host_class.new(
        runtime_context: runtime_context(tenant_override: nil, operation_override: nil),
      )

      expect(runtime_host.send(:tenant)).to eq(tenant)
      expect(catalog_host.send(:tenant)).to eq(tenant)
      expect(default_host.send(:tenant)).to eq(Tenant.default_tenant)
      expect(catalog_host.send(:operation)).to eq(operation)
    end
  end

  describe SkillCatalogDesigner::ReadSkillTool do
    include_context "with skill designer coverage setup"

    it "covers tenant-scoped lookup and missing-skill errors" do
      visible_skill = create(:skill, skill_catalog:, name: "visible-skill")
      foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
      foreign_catalog = create(:skill_catalog, operation: foreign_tenant.default_operation, name: "Foreign")
      foreign_skill = create(:skill, skill_catalog: foreign_catalog, name: "foreign-skill")
      tool = described_class.new(runtime_context: runtime_context(operation_override: nil))

      expect(tool.execute(skill_id: visible_skill.id)).to include("visible-skill")
      expect(tool.execute(skill_id: foreign_skill.id)).to eq("Error: Skill '#{foreign_skill.id}' was not found.")
    end

    it "covers lookup fallbacks from the current skill" do
      skill = create(:skill, skill_catalog:, name: "fallback-skill")
      tool = described_class.new(
        runtime_context: runtime_context(tenant_override: nil, operation_override: nil),
        current_skill: skill,
      )

      expect(tool.send(:current_skill_operation)).to eq(operation)
      expect(tool.send(:tenant)).to eq(tenant)
    end

    it "covers the Current tenant fallback" do
      bare_context = runtime_context(tenant_override: nil, operation_override: nil)

      Current.set(tenant:) do
        expect(described_class.new(runtime_context: bare_context).send(:tenant)).to eq(tenant)
      end
    end

    it "covers missing-skill and unexpected read errors" do
      skill = create(:skill, skill_catalog:, name: "error-skill")
      tool = described_class.new(runtime_context:)

      expect(tool.execute(skill_id: "missing-skill")).to eq("Error: Skill 'missing-skill' was not found.")
      allow(tool).to receive(:resolve_skill).and_return(skill)
      allow(tool).to receive(:summary_section).and_raise(StandardError, "boom")
      expect(tool.execute).to eq("Error reading skill: boom")
    end
  end

  describe SkillCatalogDesigner::ReadSkillCatalogTool do
    include_context "with skill designer coverage setup"

    it "resolves the surrounding catalog from a current skill page" do
      skill = create(:skill, skill_catalog:, name: "page-skill")
      tool = described_class.new(
        runtime_context: runtime_context(
          current_object: { "class_name" => "Skill", "type" => "Skill", "id" => skill.id },
        ),
      )

      expect(tool.execute).to include("Support Playbooks")
    end
  end
end
