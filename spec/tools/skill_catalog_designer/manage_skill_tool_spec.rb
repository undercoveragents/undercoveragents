# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillCatalogDesigner::ManageSkillTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:skill_catalog) { create(:skill_catalog, operation:, name: "Support Playbooks") }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def runtime_context_for(path:, current_object:)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: {
        "page" => { "path" => path },
        "current_object" => current_object,
      },
      user:,
      tenant:,
      operation:,
    )
  end

  def attach_user_file(filename:, content:, content_type: "text/markdown")
    message = chat.messages.create!(role: :user, content: "Please use the attached file.")
    message.attachments.attach(io: StringIO.new(content), filename:, content_type:)
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

  def build_builtin_restore_tool
    builtin_catalog = create(
      :skill_catalog,
      :builtin,
      operation: tenant.headquarter_operation,
      name: "Builtin Guides",
      source_metadata: { "builtin_key" => "undercover-agents-skills" },
    )
    builtin_skill = create(
      :skill,
      :builtin,
      skill_catalog: builtin_catalog,
      name: "support-triage",
      source_metadata: { "builtin_key" => "support-triage" },
    )
    context = runtime_context_for(
      path: Rails.application.routes.url_helpers.admin_skill_catalog_skill_path(builtin_catalog, builtin_skill),
      current_object: { "class_name" => "Skill", "id" => builtin_skill.id },
    )

    [described_class.new(runtime_context: context, current_skill: builtin_skill), builtin_skill]
  end

  def build_catalog_tool
    context = runtime_context_for(
      path: Rails.application.routes.url_helpers.admin_skill_catalog_path(skill_catalog),
      current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
    )

    described_class.new(runtime_context: context, current_skill_catalog: skill_catalog)
  end

  def expect_catalog_refresh
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(
        type: "refresh",
        path: Rails.application.routes.url_helpers.admin_skill_catalog_path(skill_catalog),
      ),
    )
  end

  describe "#name" do
    it "returns manage_skill" do
      context = runtime_context_for(
        path: Rails.application.routes.url_helpers.admin_skill_catalog_path(skill_catalog),
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )

      expect(described_class.new(runtime_context: context).name).to eq("manage_skill")
    end
  end

  describe "#execute" do
    it "creates a skill in the current catalog and refreshes the page" do
      tool = build_catalog_tool

      result = tool.execute(
        action: "create",
        attributes: {
          name: "escalation-playbook",
          description: "Escalation guidance",
          instructions: "# Escalate\n",
        },
      )

      expect(result).to include("Skill created successfully.", "escalation-playbook")
      expect(skill_catalog.skills.find_by(name: "escalation-playbook")).to be_present
      expect_catalog_refresh
    end

    it "updates a skill metadata payload and adds current message attachments as resources" do
      skill = create(:skill, skill_catalog:, name: "triage-ticket")
      attach_user_file(filename: "checklist.md", content: "Checklist")
      context = runtime_context_for(
        path: Rails.application.routes.url_helpers.admin_skill_catalog_skill_path(skill_catalog, skill),
        current_object: { "class_name" => "Skill", "id" => skill.id },
      )
      tool = described_class.new(runtime_context: context, current_skill: skill)

      result = tool.execute(
        action: "update",
        skill_id: skill.id,
        attributes: {
          metadata: { topic: "support" },
          use_current_message_attachments: true,
          resource_directory: "references",
        },
      )

      expect(result).to include("Skill updated successfully.")
      expect(skill.reload.metadata).to eq("topic" => "support")
      expect(skill.skill_resources.pluck(:relative_path)).to include("references/checklist.md")
    end

    it "imports a single skill from the latest user attachment" do
      attach_user_file(filename: "support-triage.md", content: valid_skill_markdown("support-triage"))
      context = runtime_context_for(
        path: Rails.application.routes.url_helpers.admin_skill_catalog_path(skill_catalog),
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )
      tool = described_class.new(runtime_context: context, current_skill_catalog: skill_catalog)

      result = tool.execute(action: "import")

      expect(result).to include("Action: `import`", "Imported 1 skill from support-triage.md.")
      expect(skill_catalog.skills.imported.find_by(name: "support-triage")).to be_present
    end

    it "restores a builtin skill" do
      tool, _builtin_skill = build_builtin_restore_tool

      allow(BuiltinSkills::Synchronizer).to receive(:restore!).with("undercover-agents-skills", tenant:)

      result = Current.set(operation: tenant.headquarter_operation, tenant:) do
        tool.execute(action: "restore")
      end

      expect(result).to include("Built-in skill restored to the shipped defaults.")
    end
  end
end
