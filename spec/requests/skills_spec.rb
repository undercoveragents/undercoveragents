# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe "Skills" do
  let(:skill_catalog) { create(:skill_catalog) }

  describe "GET /admin/skill_catalogs/:skill_catalog_id/skills/:id" do
    it "returns a successful response" do
      skill = create(:skill, skill_catalog:)

      get admin_skill_catalog_skill_path(skill_catalog, skill)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(skill.name)
    end
  end

  describe "GET /admin/skill_catalogs/:skill_catalog_id/skills/new" do
    it "returns a successful response" do
      get new_admin_skill_catalog_skill_path(skill_catalog)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Skill")
    end
  end

  describe "GET /admin/skill_catalogs/:skill_catalog_id/skills/:id/edit" do
    it "returns a successful response" do
      skill = create(:skill, skill_catalog:)

      get edit_admin_skill_catalog_skill_path(skill_catalog, skill)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Skill")
    end
  end

  describe "POST /admin/skill_catalogs/:skill_catalog_id/skills" do
    it "creates a manual skill and uploads resources" do
      expect do
        post admin_skill_catalog_skills_path(skill_catalog), params: {
          skill: {
            name: "renewal-playbook",
            description: "Use this skill when a customer renewal needs messaging guidance.",
            instructions: "# Renewal Playbook",
            metadata_json: '{"author":"ops"}',
            resource_directory: "references",
            resource_files: [build_resource_upload],
          },
        }
      end.to change(Skill, :count).by(1).and change(SkillResource, :count).by(1)

      skill = Skill.last
      expect(skill.metadata).to eq("author" => "ops")
      expect(skill.skill_resources.first.relative_path).to eq("references/checklist.md")
      expect(response).to redirect_to(admin_skill_catalog_skill_path(skill_catalog, skill))
    end

    it "re-renders when metadata JSON is invalid" do
      expect do
        post admin_skill_catalog_skills_path(skill_catalog), params: {
          skill: {
            name: "renewal-playbook",
            description: "Use this skill when a customer renewal needs messaging guidance.",
            metadata_json: "{invalid",
          },
        }
      end.not_to change(Skill, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/skill_catalogs/:skill_catalog_id/skills/:id" do
    it "updates the skill and removes selected resources" do
      skill = create(:skill, skill_catalog:)
      resource = create(:skill_resource, skill:, relative_path: "references/old.md")

      patch admin_skill_catalog_skill_path(skill_catalog, skill), params: {
        skill: {
          name: skill.name,
          description: skill.description,
          instructions: "# Updated",
          metadata_json: "{}",
          remove_resource_ids: [resource.id],
        },
      }

      expect(response).to redirect_to(admin_skill_catalog_skill_path(skill_catalog, skill))
      expect(skill.reload.instructions).to eq("# Updated")
      expect(skill.skill_resources).to be_empty
    end

    it "re-renders when metadata JSON is invalid" do
      skill = create(:skill, skill_catalog:)

      patch admin_skill_catalog_skill_path(skill_catalog, skill), params: {
        skill: {
          name: skill.name,
          description: skill.description,
          metadata_json: "{invalid",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /admin/skill_catalogs/:skill_catalog_id/skills/:id" do
    it "deletes the skill" do
      skill = create(:skill, skill_catalog:)

      expect do
        delete admin_skill_catalog_skill_path(skill_catalog, skill)
      end.to change(Skill, :count).by(-1)

      expect(response).to redirect_to(admin_skill_catalog_path(skill_catalog))
    end
  end

  describe "GET /admin/skill_catalogs/:skill_catalog_id/skills/import" do
    it "returns a successful response" do
      get import_admin_skill_catalog_skills_path(skill_catalog)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Import Skill")
    end
  end

  describe "POST /admin/skill_catalogs/:skill_catalog_id/skills/import" do
    it "imports a zipped skill with bundled resources" do
      expect do
        post import_admin_skill_catalog_skills_path(skill_catalog), params: {
          archive: build_zip_upload(
            "pricing/SKILL.md" => <<~MARKDOWN,
              ---
              name: pricing-guide
              description: Use this skill when pricing or packaging guidance is needed.
              ---

              # Pricing Guide
            MARKDOWN
            "pricing/references/faq.md" => "FAQ",
          ),
        }
      end.to change(Skill, :count).by(1).and change(SkillResource, :count).by(1)

      expect(response).to redirect_to(admin_skill_catalog_skill_path(skill_catalog, Skill.last))
    end

    it "re-renders when no upload is provided" do
      post import_admin_skill_catalog_skills_path(skill_catalog)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "re-renders when the uploaded skill is invalid" do
      post import_admin_skill_catalog_skills_path(skill_catalog), params: {
        archive: build_markdown_upload("# Missing frontmatter\n", filename: "SKILL.md"),
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /admin/skill_catalogs/:skill_catalog_id/skills/:id/restore" do
    it "restores a builtin skill through its parent builtin catalog" do
      BuiltinSkills::Synchronizer.ensure_present!(keys: ["undercover-agents-missions"])
      skill_catalog = SkillCatalog.find_by!(source_type: "builtin")
      skill = skill_catalog.skills.builtin.find { |item| item.builtin_key == "mission-designer-handbook" }
      skill.update!(instructions: "Customized handbook")
      post switch_admin_operation_path(skill_catalog.operation),
           headers: { "HTTP_REFERER" => admin_skill_catalog_path(skill_catalog) }

      post restore_admin_skill_catalog_skill_path(skill_catalog, skill)

      expect(response).to redirect_to(admin_skill_catalog_skill_path(skill_catalog.reload, skill.reload))
      expect(skill.reload.instructions).not_to eq("Customized handbook")
    end

    it "restores a builtin skill when restore authorization is explicitly allowed" do
      BuiltinSkills::Synchronizer.ensure_present!(keys: ["undercover-agents-missions"])
      skill_catalog = SkillCatalog.find_by!(source_type: "builtin")
      skill = skill_catalog.skills.builtin.find { |item| item.builtin_key == "mission-designer-handbook" }
      skill.update!(instructions: "Customized handbook")
      post switch_admin_operation_path(skill_catalog.operation),
           headers: { "HTTP_REFERER" => admin_skill_catalog_path(skill_catalog) }
      allow(SkillPolicy).to receive(:new).and_wrap_original do |original, user, record|
        policy = original.call(user, record)
        allow(policy).to receive(:restore?).and_return(true) if record == skill
        policy
      end

      post restore_admin_skill_catalog_skill_path(skill_catalog, skill)

      expect(response).to redirect_to(admin_skill_catalog_skill_path(skill_catalog.reload, skill.reload))
      expect(skill.reload.instructions).not_to eq("Customized handbook")
    end

    it "raises not found for a non-builtin skill" do
      skill = create(:skill, skill_catalog:)

      post restore_admin_skill_catalog_skill_path(skill_catalog, skill)

      expect(response).to have_http_status(:not_found)
    end
  end

  def build_resource_upload
    tempfile = Tempfile.new(["checklist", ".md"])
    tempfile.write("# Checklist")
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "text/markdown", original_filename: "checklist.md")
  end

  def build_markdown_upload(content, filename:)
    tempfile = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tempfile.write(content)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "text/markdown", original_filename: filename)
  end

  def build_zip_upload(entries)
    tempfile = Tempfile.new(["skill", ".zip"])
    Zip::File.open(tempfile.path, create: true) do |zip|
      entries.each do |path, content|
        zip.get_output_stream(path) { |stream| stream.write(content) }
      end
    end
    Rack::Test::UploadedFile.new(tempfile.path, "application/zip", original_filename: "skill.zip")
  end
end
