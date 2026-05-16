# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillCatalogDesigner::ManageSkillCatalogActionTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:headquarter) { tenant.headquarter_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:skill_catalog) { create(:skill_catalog, operation:, name: "Support Playbooks") }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def runtime_context_for(current_operation, path:, current_object: nil)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: {
        "page" => { "path" => path },
        "current_object" => current_object,
      }.compact,
      user:,
      tenant:,
      operation: current_operation,
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

  describe "#name" do
    it "returns manage_skill_catalog_action" do
      context = runtime_context_for(
        operation,
        path: Rails.application.routes.url_helpers.admin_skill_catalog_path(skill_catalog),
      )

      expect(described_class.new(runtime_context: context).name).to eq("manage_skill_catalog_action")
    end
  end

  describe "#execute" do
    it "attaches an agent to a skill catalog" do
      agent_record = create(:agent, operation:, name: "Support Agent", model_id: "gpt-4.1")
      context = runtime_context_for(
        operation,
        path: Rails.application.routes.url_helpers.admin_skill_catalog_path(skill_catalog),
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )
      tool = described_class.new(runtime_context: context, current_skill_catalog: skill_catalog)

      result = tool.execute(action: "attach_agent", agent_id: agent_record.id)

      expect(result).to include("Action: `attach_agent`", "Support Agent")
      expect(agent_record.reload.skill_catalog_ids).to include(skill_catalog.id)
    end

    it "imports a skill collection into the current catalog from the latest user attachment" do
      attach_user_file(filename: "support-triage.md", content: valid_skill_markdown("support-triage"))
      context = runtime_context_for(
        operation,
        path: Rails.application.routes.url_helpers.admin_skill_catalog_path(skill_catalog),
        current_object: { "class_name" => "SkillCatalog", "id" => skill_catalog.id },
      )
      tool = described_class.new(runtime_context: context, current_skill_catalog: skill_catalog)

      result = tool.execute(action: "import_collection")

      expect(result).to include("Action: `import_collection`", "Imported 1 skill from support-triage.md.")
      expect(skill_catalog.skills.imported.find_by(name: "support-triage")).to be_present
    end

    it "restores all builtin skill catalogs in Headquarter" do
      context = runtime_context_for(headquarter, path: Rails.application.routes.url_helpers.admin_skill_catalogs_path)
      tool = described_class.new(runtime_context: context)

      allow(BuiltinSkills::Synchronizer).to receive(:restore_all!).with(tenant:).and_return(
        double(restored_keys: ["undercover-agents-skills"], created_keys: ["undercover-agents-tools"]),
      )

      result = Current.set(operation: headquarter, tenant:) do
        tool.execute(action: "restore_defaults")
      end

      expect(result).to include("Restored 2 built-in skill catalogs.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "refresh", path: Rails.application.routes.url_helpers.admin_skill_catalogs_path),
      )
    end
  end
end
