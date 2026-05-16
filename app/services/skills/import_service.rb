# frozen_string_literal: true

require "zip"

module Skills
  class ImportService
    class ImportError < StandardError; end

    Package = Data.define(:directory_name, :content, :resources)
    Result = Data.define(:catalog, :skills, :created_count, :updated_count, :warnings)

    def initialize(catalog:, upload:, mode: :collection)
      @catalog = catalog
      @upload = upload
      @mode = mode.to_sym
      @parser = FrontmatterParser.new
    end

    def call
      packages = validated_packages
      counters = { created_count: 0, updated_count: 0 }
      warnings = []
      skills = packages.map { |package| import_package(package, counters:, warnings:) }

      Result.new(catalog:, skills:, warnings: warnings.uniq, **counters)
    end

    private

    attr_reader :catalog, :upload, :mode, :parser

    def extract_packages
      zip_upload? ? packages_from_zip : [package_from_markdown_upload].compact
    end

    def validated_packages
      packages = extract_packages
      raise ImportError, "No skills were found in the uploaded file." if packages.empty?
      raise ImportError, "The uploaded file must contain exactly one skill." if mode == :single && packages.size != 1

      packages
    end

    def import_package(package, counters:, warnings:)
      result = parsed_package(package)
      skill, new_record = build_skill(result)

      increment_counters(counters, new_record)
      save_imported_skill(skill, result)
      replace_resources!(skill, package.resources)

      warnings.concat(result.warnings.map { |warning| "#{skill.name}: #{warning}" })
      skill
    end

    def parsed_package(package)
      result = parser.parse(package.content, directory_name: package.directory_name)
      raise ImportError, result.error_message unless result.success?

      result
    end

    def build_skill(result)
      skill = catalog.skills.find_or_initialize_by(name: result.attributes[:name])
      [skill, skill.new_record?]
    end

    def increment_counters(counters, new_record)
      counter_key = new_record ? :created_count : :updated_count
      counters[counter_key] += 1
    end

    def save_imported_skill(skill, result)
      skill.assign_attributes(imported_attributes(result))
      skill.save!
    end

    def imported_attributes(result)
      result.attributes.merge(
        source_type: "imported",
        source_metadata: result.attributes.fetch(:source_metadata, {}).merge(
          "imported_from" => upload.original_filename,
          "warnings" => result.warnings,
        ),
      )
    end

    def zip_upload?
      File.extname(upload.original_filename.to_s).casecmp(".zip").zero?
    end

    def package_from_markdown_upload
      content = upload.read
      upload.rewind if upload.respond_to?(:rewind)
      return if content.blank?

      directory_name = File.basename(upload.original_filename.to_s, ".*")
      Package.new(directory_name:, content:, resources: {})
    end

    def packages_from_zip
      Zip::File.open(upload.tempfile.path) do |zip_file|
        entries = filtered_zip_entries(zip_file)
        skill_entries(entries).map { |skill_entry| build_zip_package(skill_entry, entries) }
      end
    end

    def filtered_zip_entries(zip_file)
      zip_file.entries.reject(&:directory?).reject { |entry| ignored_entry?(entry.name) }
    end

    def skill_entries(entries)
      entries.select { |entry| File.basename(entry.name) == "SKILL.md" }
    end

    def build_zip_package(skill_entry, entries)
      prefix = entry_prefix(skill_entry.name)

      Package.new(
        directory_name: package_directory_name(skill_entry.name),
        content: skill_entry.get_input_stream.read,
        resources: zip_package_resources(entries, prefix:, skill_entry_name: skill_entry.name),
      )
    end

    def zip_package_resources(entries, prefix:, skill_entry_name:)
      entries.filter_map do |entry|
        next if entry.name == skill_entry_name
        next unless entry.name.start_with?(prefix)

        relative_path = sanitize_relative_path(entry.name.delete_prefix(prefix))
        # :nocov:
        next if relative_path.blank?
        # :nocov:

        [relative_path, entry.get_input_stream.read]
      end.to_h
    end

    def ignored_entry?(path)
      clean_path = path.to_s.tr("\\", "/")
      clean_path.start_with?("__MACOSX/", ".DS_Store") || clean_path.split("/").include?("..")
    end

    def package_directory_name(skill_md_path)
      clean_path = skill_md_path.to_s.tr("\\", "/")
      parent = File.dirname(clean_path)
      return File.basename(upload.original_filename.to_s, ".zip") if parent == "."

      File.basename(parent)
    end

    def entry_prefix(skill_md_path)
      clean_path = skill_md_path.to_s.tr("\\", "/")
      parent = File.dirname(clean_path)
      parent == "." ? "" : "#{parent}/"
    end

    def sanitize_relative_path(path)
      clean_path = path.to_s.tr("\\", "/").squeeze("/").delete_prefix("/")
      return if clean_path.blank?
      return if clean_path.split("/").include?("..")

      clean_path
    end

    def replace_resources!(skill, resources)
      skill.skill_resources.destroy_all
      resources.each do |relative_path, content|
        resource = skill.skill_resources.build(relative_path:)
        resource.file.attach(
          io: StringIO.new(content),
          filename: File.basename(relative_path),
          content_type: Marcel::MimeType.for(name: relative_path),
        )
        resource.save!
      end
    end
  end
end
