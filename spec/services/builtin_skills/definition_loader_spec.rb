# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe BuiltinSkills::DefinitionLoader do
  describe ".load_all" do
    subject(:definitions) { described_class.load_all.index_by(&:key) }

    it "loads application and plugin builtin skill catalogs" do
      expect(definitions.keys).to include(
        "undercover-agents-admin",
        "undercover-agents-agents",
        "undercover-agents-channels",
        "undercover-agents-missions",
        "undercover-agents-skills",
        "undercover-agents-test-suites",
        "undercover-agents-tools",
        "undercover-agents-rag",
      )
    end

    it "loads the missions catalog with stable skill keys" do
      definition = definitions.fetch("undercover-agents-missions")

      expect(definition.name).to eq("Missions")
      expect(definition.skills.map(&:key)).to include("mission-designer-workbench", "mission-designer-handbook")
      expect(definition.skills.find { |skill| skill.key == "mission-designer-handbook" }&.description)
        .to include("workflow process")
    end

    it "reuses parsed definitions when tracked files are unchanged" do
      Dir.mktmpdir do |dir|
        catalog_dir = build_temp_catalog(dir)

        allow(described_class).to receive(:definition_paths).and_return([catalog_dir.join("CATALOG.md").to_s])
        allow(described_class).to receive(:load_catalog).and_call_original

        first = described_class.load_all
        second = described_class.load_all

        expect(first.map(&:key)).to eq(["tmp-catalog"])
        expect(second.map(&:key)).to eq(["tmp-catalog"])
        expect(described_class).to have_received(:load_catalog).once
      end
    end
  end

  describe "private helpers" do
    it "handles tracked files disappearing while building a signature" do
      missing_path = "/tmp/missing-resource"
      allow(described_class).to receive(:tracked_paths_for_catalog).and_return([missing_path])
      allow(File).to receive(:stat).with(missing_path).and_raise(Errno::ENOENT)

      signature = described_class.send(:definition_signature, ["/tmp/catalog/CATALOG.md"])

      expect(signature).to eq([[missing_path, nil, nil, nil]])
    end

    it "raises when a builtin catalog frontmatter is malformed" do
      Dir.mktmpdir do |dir|
        catalog_dir = Pathname.new(dir).join("broken-catalog")
        catalog_dir.mkpath
        catalog_path = catalog_dir.join("CATALOG.md")
        catalog_path.write("---\ndescription: [broken\n---\n")
        catalog_dir.join("placeholder").mkpath
        catalog_dir.join("placeholder/SKILL.md").write(valid_skill_markdown("placeholder"))

        expect do
          described_class.send(:load_catalog, catalog_path)
        end.to raise_error(/frontmatter could not be parsed/)
      end
    end

    it "raises when a builtin catalog does not contain any skill packages" do
      Dir.mktmpdir do |dir|
        catalog_dir = Pathname.new(dir).join("empty-catalog")
        catalog_dir.mkpath
        catalog_path = catalog_dir.join("CATALOG.md")
        catalog_path.write(<<~MARKDOWN)
          ---
          name: Empty Catalog
          description: No skill packages.
          ---
        MARKDOWN

        expect do
          described_class.send(:load_catalog, catalog_path)
        end.to raise_error(/must contain at least one SKILL\.md package/)
      end
    end

    it "raises when a builtin catalog is missing YAML frontmatter" do
      Dir.mktmpdir do |dir|
        catalog_path = Pathname.new(dir).join("CATALOG.md")
        catalog_path.write("No frontmatter")

        expect do
          described_class.send(:load_catalog_metadata, catalog_path, directory_name: "missing-frontmatter")
        end.to raise_error(/must start with YAML frontmatter/)
      end
    end

    it "raises when a builtin catalog frontmatter omits description" do
      Dir.mktmpdir do |dir|
        catalog_path = Pathname.new(dir).join("CATALOG.md")
        catalog_path.write("---\nplaceholder: value\n---\n")
        allow(YAML).to receive(:safe_load).and_return(nil)

        expect do
          described_class.send(:load_catalog_metadata, catalog_path, directory_name: "missing-description")
        end.to raise_error(/must include a non-empty description/)
      end
    end

    it "raises when a builtin skill package cannot be parsed" do
      path = Pathname.new("/tmp/catalog/bad-skill/SKILL.md")
      parser = instance_double(Skills::FrontmatterParser)
      result = Skills::FrontmatterParser::Result.new(
        attributes: {},
        warnings: [],
        error_message: "invalid package",
      )

      allow(path).to receive(:read).and_return("content")
      allow(Skills::FrontmatterParser).to receive(:new).and_return(parser)
      allow(parser).to receive(:parse).with("content", directory_name: "bad-skill").and_return(result)

      expect do
        described_class.send(:parsed_skill_result, path)
      end.to raise_error("Builtin skill #{path}: invalid package")
    end

    it "raises when a builtin skill package lives at the catalog root" do
      catalog_dir = Pathname.new("/tmp/catalog")
      skill_path = catalog_dir.join("SKILL.md")

      expect do
        described_class.send(:skill_key_for, skill_path, catalog_dir)
      end.to raise_error(/must live in a subdirectory under its catalog/)
    end

    it "raises when duplicate builtin skill catalog keys are discovered" do
      duplicate = instance_double(BuiltinSkills::CatalogDefinition, key: "duplicate")

      expect do
        described_class.send(:ensure_unique_catalog_keys!, [duplicate, duplicate])
      end.to raise_error("Duplicate builtin skill catalog keys detected: duplicate")
    end

    it "raises when a catalog defines duplicate builtin skill keys" do
      skill = instance_double(BuiltinSkills::SkillDefinition, key: "duplicate-skill")
      definition = instance_double(BuiltinSkills::CatalogDefinition, key: "catalog", skills: [skill, skill])

      expect do
        described_class.send(:ensure_unique_skill_keys!, definition)
      end.to raise_error("Duplicate builtin skill keys detected in catalog: duplicate-skill")
    end
  end

  def build_temp_catalog(dir)
    catalog_dir = Pathname.new(dir).join("tmp-catalog")
    catalog_dir.mkpath
    catalog_dir.join("CATALOG.md").write(<<~MARKDOWN)
      ---
      name: Temp Catalog
      description: Temp description.
      ---
    MARKDOWN

    skill_dir = catalog_dir.join("temp-skill")
    skill_dir.mkpath
    skill_dir.join("SKILL.md").write(<<~MARKDOWN)
      ---
      name: temp-skill
      description: Temp skill.
      ---

      # Temp Skill
    MARKDOWN

    catalog_dir
  end

  def valid_skill_markdown(name)
    <<~MARKDOWN
      ---
      name: #{name}
      description: Temp skill for #{name}.
      ---

      # #{name.titleize}
    MARKDOWN
  end
end
