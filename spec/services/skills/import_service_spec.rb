# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe Skills::ImportService do
  let(:catalog) { create(:skill_catalog) }

  describe "#call" do
    it "imports every discovered skill from a zip collection" do
      upload = build_zip_upload(
        "collection/renewal-email/SKILL.md" => <<~MARKDOWN,
          ---
          name: renewal-email
          description: Use this skill when drafting or reviewing renewal outreach.
          ---

          # Renewal Email
        MARKDOWN
        "collection/renewal-email/references/template.md" => "Template",
        "collection/escalation-playbook/SKILL.md" => <<~MARKDOWN,
          ---
          name: escalation-playbook
          description: Use this skill when a support request needs escalation handling.
          ---

          # Escalation Playbook
        MARKDOWN
      )

      result = described_class.new(catalog:, upload:, mode: :collection).call
      renewal_skill = catalog.skills.find_by!(name: "renewal-email")

      expect(result.skills.map(&:name)).to contain_exactly("renewal-email", "escalation-playbook")
      expect(renewal_skill.skill_resources.pluck(:relative_path)).to include("references/template.md")
    end

    it "raises when no skills are discovered in the upload" do
      upload = build_zip_upload("notes/readme.md" => "Just notes")

      expect do
        described_class.new(catalog:, upload:, mode: :collection).call
      end.to raise_error(described_class::ImportError, "No skills were found in the uploaded file.")
    end

    it "raises when single mode receives multiple skills" do
      upload = build_zip_upload(
        "one/SKILL.md" => valid_skill_markdown("one"),
        "two/SKILL.md" => valid_skill_markdown("two"),
      )

      expect do
        described_class.new(catalog:, upload:, mode: :single).call
      end.to raise_error(described_class::ImportError, "The uploaded file must contain exactly one skill.")
    end

    it "updates an existing skill and replaces bundled resources" do
      existing_skill = create(:skill, skill_catalog: catalog, name: "renewal-email", instructions: "Old")
      create(:skill_resource, skill: existing_skill, relative_path: "references/old.md")
      upload = build_zip_upload(
        "collection/renewal-email/SKILL.md" => valid_skill_markdown("renewal-email"),
        "collection/renewal-email/references/new.md" => "New resource",
      )

      result = described_class.new(catalog:, upload:, mode: :collection).call

      expect(result.created_count).to eq(0)
      expect(result.updated_count).to eq(1)
      expect(existing_skill.reload.instructions).to include("Renewal Email")
      expect(existing_skill.skill_resources.pluck(:relative_path)).to contain_exactly("references/new.md")
    end

    it "recovers common YAML values with unquoted colons" do
      upload = build_markdown_upload(
        <<~MARKDOWN,
          ---
          name: support-triage
          description: Use this skill when: a support request needs escalation guidance.
          ---

          # Support Triage
        MARKDOWN
        filename: "SKILL.md",
      )

      result = described_class.new(catalog:, upload:, mode: :single).call

      expect(result.skills.first.description).to eq("Use this skill when: a support request needs escalation guidance.")
    end

    it "returns nil for blank markdown uploads" do
      upload = build_markdown_upload("", filename: "blank.md")
      service = described_class.new(catalog:, upload:, mode: :single)

      expect(service.send(:package_from_markdown_upload)).to be_nil
    end

    it "imports markdown uploads that do not support rewind" do
      upload = Class.new do
        attr_reader :original_filename

        def initialize(original_filename, content)
          @original_filename = original_filename
          @content = content
        end

        def read
          @content
        end
      end.new("support-triage.md", valid_skill_markdown("support-triage"))

      service = described_class.new(catalog:, upload:, mode: :single)

      package = service.send(:package_from_markdown_upload)

      expect(package.directory_name).to eq("support-triage")
      expect(package.content).to include("name: support-triage")
    end

    it "uses the archive name for root-level zip skills" do
      upload = build_zip_upload("SKILL.md" => valid_skill_markdown("root-skill"))

      result = described_class.new(catalog:, upload:, mode: :single).call

      expect(result.skills.first.source_metadata["directory_name"]).to eq("skills")
    end

    it "returns nil for unsafe or blank relative paths" do
      service = described_class.new(catalog:, upload: build_markdown_upload("", filename: "blank.md"), mode: :single)

      expect(service.send(:sanitize_relative_path, "")).to be_nil
      expect(service.send(:sanitize_relative_path, "../secret.txt")).to be_nil
    end

    it "skips zip resources whose relative path collapses to blank" do
      service = described_class.new(catalog:, upload: build_markdown_upload("", filename: "blank.md"), mode: :single)
      entry = instance_spy(Zip::Entry, name: "collection/renewal-email/")

      resources = service.send(
        :zip_package_resources,
        [entry],
        prefix: "collection/renewal-email/",
        skill_entry_name: "collection/renewal-email/SKILL.md",
      )

      expect(entry).not_to have_received(:get_input_stream)
      expect(resources).to eq({})
    end
  end

  def build_markdown_upload(content, filename:)
    tempfile = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tempfile.write(content)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "text/markdown", original_filename: filename)
  end

  def build_zip_upload(entries)
    tempfile = Tempfile.new(["skill-import", ".zip"])
    Zip::File.open(tempfile.path, create: true) do |zip|
      entries.each do |path, content|
        zip.get_output_stream(path) { |stream| stream.write(content) }
      end
    end
    Rack::Test::UploadedFile.new(tempfile.path, "application/zip", original_filename: "skills.zip")
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
