# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillResourceReaderTool do
  describe "#name" do
    it "returns the runtime tool name" do
      tool = described_class.new(instance_double(Skills::AssignedRegistry, find: nil))

      expect(tool.name).to eq("read_skill_resource")
    end
  end

  describe "#execute" do
    it "returns a not found message when the skill does not exist" do
      tool = described_class.new(instance_double(Skills::AssignedRegistry, find: nil))

      expect(tool.execute(skill_identifier: "missing", path: "references/guide.md")).to eq(
        "The selected skill could not be found.",
      )
    end

    it "returns a not found message when the resource does not exist" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      tool = described_class.new(build_registry(skill_catalog))

      expect(tool.execute(skill_identifier: "#{skill_catalog.slug}/#{skill.id}", path: "missing.md")).to eq(
        "The requested skill resource could not be found.",
      )
    end

    it "reads text resources and normalizes the requested path" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      create(:skill_resource, skill:, relative_path: "references/guide.md")
      tool = described_class.new(build_registry(skill_catalog))

      result = tool.execute(skill_identifier: "#{skill_catalog.slug}/#{skill.id}", path: "/references//guide.md")

      expect(result).to include("<skill_resource")
      expect(result).to include("Reference content")
    end

    it "truncates large text resources" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      create_large_text_resource(skill)
      tool = described_class.new(build_registry(skill_catalog))

      result = tool.execute(skill_identifier: "#{skill_catalog.slug}/#{skill.id}", path: "references/large.txt")

      expect(result).to include("[truncated]")
    end

    it "returns metadata for binary resources" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      create_binary_resource(skill)
      tool = described_class.new(build_registry(skill_catalog))

      result = tool.execute(skill_identifier: "#{skill_catalog.slug}/#{skill.id}", path: "assets/blob.bin")

      expect(result).to include("This file is not UTF-8 text")
      expect(result).to include("Content type:")
      expect(result).to include("File size:")
    end
  end

  def build_registry(skill_catalog)
    agent = create(:agent, operation: skill_catalog.operation)
    agent.update!(skill_catalog_ids: [skill_catalog.id])
    Skills::AssignedRegistry.new(agent)
  end

  def create_large_text_resource(skill)
    resource = skill.skill_resources.build(relative_path: "references/large.txt")
    resource.file.attach(
      io: StringIO.new("A" * (described_class::MAX_TEXT_BYTES + 10)),
      filename: "large.txt",
      content_type: "text/plain",
    )
    resource.save!
  end

  def create_binary_resource(skill)
    resource = skill.skill_resources.build(relative_path: "assets/blob.bin")
    resource.file.attach(
      io: StringIO.new([0xFF, 0xFE, 0x00, 0x01].pack("C*")),
      filename: "blob.bin",
      content_type: "application/octet-stream",
    )
    resource.save!
  end
end
