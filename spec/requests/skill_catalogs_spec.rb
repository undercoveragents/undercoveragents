# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe "SkillCatalogs" do
  describe "GET /admin/skill_catalogs" do
    it "returns a successful response" do
      get admin_skill_catalogs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Skill Catalogs")
    end
  end

  describe "GET /admin/skill_catalogs/:id" do
    it "returns a successful response" do
      skill_catalog = create(:skill_catalog, name: "Ops Library")

      get admin_skill_catalog_path(skill_catalog)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ops Library")
    end
  end

  describe "GET /admin/skill_catalogs/new" do
    it "returns a successful response" do
      get new_admin_skill_catalog_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Skill Catalog")
    end
  end

  describe "GET /admin/skill_catalogs/:id/edit" do
    it "returns a successful response" do
      skill_catalog = create(:skill_catalog)

      get edit_admin_skill_catalog_path(skill_catalog)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Skill Catalog")
    end
  end

  describe "POST /admin/skill_catalogs" do
    let(:valid_params) do
      {
        skill_catalog: {
          name: "Customer Ops Playbooks",
          description: "Operational skills for support, renewals, and escalation handling.",
        },
      }
    end

    it "creates a skill catalog" do
      expect { post admin_skill_catalogs_path, params: valid_params }
        .to change(SkillCatalog, :count).by(1)
    end

    it "redirects to the show page" do
      post admin_skill_catalogs_path, params: valid_params

      expect(response).to redirect_to(admin_skill_catalog_path(SkillCatalog.last))
    end

    it "re-renders when the catalog is invalid" do
      expect do
        post admin_skill_catalogs_path, params: { skill_catalog: { name: "", description: "Broken" } }
      end.not_to change(SkillCatalog, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/skill_catalogs/:id" do
    it "updates the catalog" do
      skill_catalog = create(:skill_catalog, name: "Old Name")

      patch admin_skill_catalog_path(skill_catalog), params: { skill_catalog: { name: "New Name" } }

      expect(response).to redirect_to(admin_skill_catalog_path(skill_catalog.reload))
      expect(skill_catalog.reload.name).to eq("New Name")
    end

    it "re-renders when the catalog is invalid" do
      skill_catalog = create(:skill_catalog)

      patch admin_skill_catalog_path(skill_catalog), params: { skill_catalog: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /admin/skill_catalogs/:id" do
    it "deletes the catalog" do
      skill_catalog = create(:skill_catalog)

      expect do
        delete admin_skill_catalog_path(skill_catalog)
      end.to change(SkillCatalog, :count).by(-1)

      expect(response).to redirect_to(admin_skill_catalogs_path)
    end
  end

  describe "GET /admin/skill_catalogs/import" do
    it "returns a successful response" do
      get import_admin_skill_catalogs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Import Skill Collection")
    end
  end

  describe "POST /admin/skill_catalogs/import" do
    it "creates a new catalog and imports a skill from SKILL.md" do
      expect do
        post import_admin_skill_catalogs_path, params: {
          target_mode: "new",
          skill_catalog: {
            name: "Imported Catalog",
            description: "Imported from an Agent Skills file.",
          },
          archive: build_markdown_upload(<<~MARKDOWN),
            ---
            name: escalation-guide
            description: Use this skill when a customer issue needs escalation guidance.
            ---

            # Escalation Guide
          MARKDOWN
        }
      end.to change(SkillCatalog, :count).by(1).and change(Skill, :count).by(1)

      expect(response).to redirect_to(admin_skill_catalog_path(SkillCatalog.last))
    end

    it "re-renders when no upload is provided" do
      post import_admin_skill_catalogs_path, params: {
        target_mode: "new",
        skill_catalog: { name: "Imported Catalog" },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "re-renders when a new target catalog is invalid" do
      expect do
        post import_admin_skill_catalogs_path, params: {
          target_mode: "new",
          skill_catalog: { name: "" },
          archive: build_markdown_upload(<<~MARKDOWN),
            ---
            name: escalation-guide
            description: Use this skill when escalation guidance is needed.
            ---

            # Escalation Guide
          MARKDOWN
        }
      end.not_to change(SkillCatalog, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "imports into an existing catalog and reports warnings" do
      skill_catalog = create(:skill_catalog, name: "Imported Catalog")

      expect do
        post import_admin_skill_catalogs_path, params: {
          target_mode: "existing",
          target_catalog_id: skill_catalog.slug,
          archive: build_zip_upload(
            "renamed-folder/SKILL.md" => <<~MARKDOWN,
              ---
              name: escalation-guide
              description: Use this skill when escalation guidance is needed.
              ---

              # Escalation Guide
            MARKDOWN
          ),
        }
      end.not_to change(SkillCatalog, :count)

      expect(response).to redirect_to(admin_skill_catalog_path(skill_catalog))
      expect(flash[:notice]).to include("1 warning")
    end

    it "re-renders when the uploaded skill is invalid" do
      post import_admin_skill_catalogs_path, params: {
        target_mode: "new",
        skill_catalog: { name: "Imported Catalog" },
        archive: build_markdown_upload("# Missing frontmatter\n"),
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /admin/skill_catalogs/:id/restore" do
    it "restores a builtin skill catalog in Headquarter" do
      BuiltinSkills::Synchronizer.ensure_present!(keys: ["undercover-agents-missions"])
      skill_catalog = SkillCatalog.find_by!(source_type: "builtin")
      skill_catalog.update!(name: "Customized Missions Catalog")
      post switch_admin_operation_path(skill_catalog.operation), headers: { "HTTP_REFERER" => admin_skill_catalogs_url }

      post restore_admin_skill_catalog_path(skill_catalog)

      expect(response).to redirect_to(admin_skill_catalog_path(skill_catalog.reload))
      expect(skill_catalog.reload.name).to eq("Missions")
    end

    it "restores a builtin skill catalog when restore authorization is explicitly allowed" do
      BuiltinSkills::Synchronizer.ensure_present!(keys: ["undercover-agents-missions"])
      skill_catalog = SkillCatalog.find_by!(source_type: "builtin")
      skill_catalog.update!(name: "Customized Missions Catalog")
      post switch_admin_operation_path(skill_catalog.operation), headers: { "HTTP_REFERER" => admin_skill_catalogs_url }
      allow(SkillCatalogPolicy).to receive(:new).and_wrap_original do |original, user, record|
        policy = original.call(user, record)
        allow(policy).to receive(:restore?).and_return(true) if record == skill_catalog
        policy
      end

      post restore_admin_skill_catalog_path(skill_catalog)

      expect(response).to redirect_to(admin_skill_catalog_path(skill_catalog.reload))
      expect(skill_catalog.reload.name).to eq("Missions")
    end

    it "raises not found for a non-builtin skill catalog" do
      post restore_admin_skill_catalog_path(create(:skill_catalog))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /admin/skill_catalogs/restore_defaults" do
    it "refuses to restore all builtin skill catalogs outside Headquarter" do
      BuiltinSkills::Synchronizer.ensure_present!(keys: ["undercover-agents-missions"])

      post restore_defaults_admin_skill_catalogs_path

      expect(response).to redirect_to(root_path)
    end

    it "restores all builtin skill catalogs in Headquarter" do
      BuiltinSkills::Synchronizer.ensure_present!(keys: ["undercover-agents-missions"])
      headquarter = SkillCatalog.find_by!(source_type: "builtin").operation
      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_skill_catalogs_url }
      allow(BuiltinSkills::Synchronizer).to receive(:restore_all!)
        .and_return(
          BuiltinSkills::Synchronizer::Result.new(
            created_keys: [],
            restored_keys: ["undercover-agents-missions"],
          ),
        )

      post restore_defaults_admin_skill_catalogs_path

      expect(response).to redirect_to(admin_skill_catalogs_path)
      expect(flash[:notice]).to eq(I18n.t("skill_catalogs.restored_all", count: 1))
    end

    it "handles the zero-restored branch" do
      BuiltinSkills::Synchronizer.ensure_present!(keys: ["undercover-agents-missions"])
      headquarter = SkillCatalog.find_by!(source_type: "builtin").operation
      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_skill_catalogs_url }

      allow(BuiltinSkills::Synchronizer).to receive(:restore_all!)
        .and_return(BuiltinSkills::Synchronizer::Result.new(created_keys: [], restored_keys: []))

      post restore_defaults_admin_skill_catalogs_path

      expect(response).to redirect_to(admin_skill_catalogs_path)
      expect(flash[:notice]).to eq(I18n.t("skill_catalogs.restored_all", count: 0))
    end
  end

  describe "POST /admin/skill_catalogs/:id/attach_agent" do
    it "attaches the catalog to the selected agent" do
      skill_catalog = create(:skill_catalog)
      agent = create(:agent, operation: skill_catalog.operation)

      post attach_agent_admin_skill_catalog_path(skill_catalog), params: { agent_id: agent.id }

      expect(agent.reload.skill_catalog_ids).to include(skill_catalog.id)
      expect(response).to redirect_to(admin_skill_catalog_path(skill_catalog))
    end

    it "re-renders the show page when the agent cannot be saved" do
      skill_catalog = create(:skill_catalog)
      agent = create(:agent, operation: skill_catalog.operation)

      allow_any_instance_of(Agent).to receive(:save).and_return(false) # rubocop:disable RSpec/AnyInstance

      post attach_agent_admin_skill_catalog_path(skill_catalog), params: { agent_id: agent.id }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /admin/skill_catalogs/:id/detach_agent" do
    it "detaches the catalog from the agent" do
      skill_catalog = create(:skill_catalog)
      agent = create(:agent, operation: skill_catalog.operation)
      agent.update!(skill_catalog_ids: [skill_catalog.id])

      delete detach_agent_admin_skill_catalog_path(skill_catalog), params: { agent_id: agent.id }

      expect(agent.reload.skill_catalog_ids).to eq([])
      expect(response).to redirect_to(admin_skill_catalog_path(skill_catalog))
    end
  end

  def build_markdown_upload(content)
    tempfile = Tempfile.new(["skill", ".md"])
    tempfile.write(content)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "text/markdown", original_filename: "SKILL.md")
  end

  def build_zip_upload(entries)
    tempfile = Tempfile.new(["skills", ".zip"])
    Zip::File.open(tempfile.path, create: true) do |zip|
      entries.each do |path, content|
        zip.get_output_stream(path) { |stream| stream.write(content) }
      end
    end
    Rack::Test::UploadedFile.new(tempfile.path, "application/zip", original_filename: "skills.zip")
  end
end
