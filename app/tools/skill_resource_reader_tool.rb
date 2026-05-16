# frozen_string_literal: true

class SkillResourceReaderTool < RubyLLM::Tool
  MAX_TEXT_BYTES = 40.kilobytes

  description "Read a bundled text file from an installed skill after that skill has been activated."

  param :skill_identifier, desc: "The skill identifier from list_available_skills output.", type: :string

  param :path,
        desc: "Relative file path inside the selected skill, such as references/REFERENCE.md or scripts/run.sh.",
        type: :string

  def initialize(registry)
    super()
    @registry = registry
  end

  def name
    "read_skill_resource"
  end

  def execute(skill_identifier:, path:)
    entry = @registry.find(skill_identifier)
    return "The selected skill could not be found." unless entry

    resource = entry.skill.skill_resources.find_by(relative_path: sanitized_path(path))
    return "The requested skill resource could not be found." unless resource

    content = resource.file.download
    text = decode_text(content)
    return binary_response(entry, resource) unless text

    <<~CONTENT.strip
      <skill_resource identifier="#{ERB::Util.h(entry.identifier)}" path="#{ERB::Util.h(resource.relative_path)}">
      #{truncate_text(text)}
      </skill_resource>
    CONTENT
  end

  private

  def sanitized_path(path)
    path.to_s.tr("\\", "/").squeeze("/").delete_prefix("/")
  end

  def decode_text(content)
    text = content.dup.force_encoding(Encoding::UTF_8)
    return text if text.valid_encoding?

    content.encode(Encoding::UTF_8)
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    nil
  end

  def truncate_text(text)
    text.bytesize > MAX_TEXT_BYTES ? "#{text.byteslice(0, MAX_TEXT_BYTES)}\n\n[truncated]" : text
  end

  def binary_response(entry, resource)
    <<~CONTENT.strip
      <skill_resource identifier="#{ERB::Util.h(entry.identifier)}" path="#{ERB::Util.h(resource.relative_path)}">
      This file is not UTF-8 text and cannot be rendered inline.
      Content type: #{resource.file.blob.content_type}
      File size: #{resource.file.blob.byte_size} bytes
      </skill_resource>
    CONTENT
  end
end
