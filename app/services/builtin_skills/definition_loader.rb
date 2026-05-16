# frozen_string_literal: true

module BuiltinSkills
  class DefinitionLoader
    DOT_ENTRIES = [".", ".."].freeze

    CATALOG_GLOBS = [
      Rails.root.join("config/builtin_skills/**/CATALOG.md").to_s,
      Rails.root.join("plugins/**/config/builtin_skills/**/CATALOG.md").to_s,
    ].freeze

    class << self
      def load_all
        paths = definition_paths
        signature = definition_signature(paths)
        return @cached_definitions if @cached_signature == signature && @cached_definitions

        definitions = paths.map { |path| load_catalog(Pathname.new(path)) }
        detect_duplicate_keys!(definitions)
        @cached_signature = signature
        @cached_definitions = definitions.sort_by(&:key).freeze
      end

      def load_for(keys)
        requested = Array(keys).map(&:to_s)
        load_all.select { |definition| definition.key.in?(requested) }
      end

      private

      def definition_paths
        CATALOG_GLOBS.flat_map { |glob| Dir.glob(glob) }.sort
      end

      def definition_signature(paths)
        paths.flat_map { |path| tracked_paths_for_catalog(Pathname.new(path).dirname) }
             .uniq
             .sort
             .map do |tracked_path|
          stat = File.stat(tracked_path)
          [tracked_path, stat.directory?, stat.mtime.to_f, stat.size]
        rescue Errno::ENOENT
          [tracked_path, nil, nil, nil]
        end
      end

      def tracked_paths_for_catalog(catalog_dir)
        [catalog_dir.to_s] + Dir.glob(catalog_dir.join("**/*").to_s, File::FNM_DOTMATCH)
                                .reject { |path| DOT_ENTRIES.include?(File.basename(path)) }
      end

      def load_catalog(path)
        catalog_dir = path.dirname
        metadata = load_catalog_metadata(path, directory_name: catalog_dir.basename.to_s)
        skills = skill_paths(catalog_dir).map do |skill_path|
          load_skill_definition(Pathname.new(skill_path), catalog_dir:)
        end

        raise "Builtin skill catalog #{path} must contain at least one SKILL.md package." if skills.empty?

        CatalogDefinition.new(
          key: catalog_dir.basename.to_s,
          name: metadata.fetch("name"),
          description: metadata.fetch("description"),
          skills:,
          source_path: path,
        )
      end

      def load_catalog_metadata(path, directory_name:)
        match = Skills::FrontmatterParser::FRONTMATTER_PATTERN.match(path.read)
        raise "Builtin skill catalog #{path} must start with YAML frontmatter." unless match

        data = YAML.safe_load(match[:yaml], aliases: true)&.deep_stringify_keys || {}
        description = data["description"].to_s.strip

        raise "Builtin skill catalog #{path} must include a non-empty description." if description.blank?

        {
          "name" => data["name"].to_s.strip.presence || directory_name.tr("-", " ").titleize,
          "description" => description,
        }
      rescue Psych::SyntaxError => e
        raise "Builtin skill catalog #{path} frontmatter could not be parsed: #{e.message}"
      end

      def skill_paths(catalog_dir)
        Dir.glob(catalog_dir.join("**/SKILL.md").to_s)
      end

      def load_skill_definition(path, catalog_dir:)
        skill_key = skill_key_for(path, catalog_dir)
        result = parsed_skill_result(path)

        SkillDefinition.new(
          key: skill_key,
          source_path: path,
          **skill_definition_attributes(path, result),
        )
      end

      def parsed_skill_result(path)
        result = Skills::FrontmatterParser.new.parse(path.read, directory_name: path.dirname.basename.to_s)
        raise "Builtin skill #{path}: #{result.error_message}" unless result.success?

        result
      end

      def skill_definition_attributes(path, result)
        attributes = result.attributes

        {
          name: attributes.fetch(:name),
          description: attributes.fetch(:description),
          instructions: attributes.fetch(:instructions),
          license: attributes[:license],
          compatibility: attributes[:compatibility],
          allowed_tools: attributes[:allowed_tools],
          metadata: attributes[:metadata],
          resources: load_skill_resources(path),
        }
      end

      def skill_key_for(path, catalog_dir)
        relative_dir = path.dirname.relative_path_from(catalog_dir).to_s.tr("\\", "/")
        raise "Builtin skill #{path} must live in a subdirectory under its catalog." if relative_dir == "."

        relative_dir
      end

      def load_skill_resources(skill_path)
        skill_dir = skill_path.dirname

        Dir.glob(skill_dir.join("**/*").to_s, File::FNM_DOTMATCH).sort.each_with_object({}) do |path, resources|
          pathname = Pathname.new(path)
          next if pathname.directory? || pathname == skill_path || DOT_ENTRIES.include?(pathname.basename.to_s)

          resources[pathname.relative_path_from(skill_dir).to_s.tr("\\", "/")] = File.binread(path)
        end
      end

      def detect_duplicate_keys!(definitions)
        ensure_unique_catalog_keys!(definitions)

        definitions.each do |definition|
          ensure_unique_skill_keys!(definition)
        end
      end

      def ensure_unique_catalog_keys!(definitions)
        duplicate_catalog_keys = definitions.group_by(&:key).select { |_key, items| items.size > 1 }.keys

        return if duplicate_catalog_keys.empty?

        raise "Duplicate builtin skill catalog keys detected: #{duplicate_catalog_keys.join(", ")}"
      end

      def ensure_unique_skill_keys!(definition)
        duplicate_skill_keys = definition.skills.group_by(&:key).select { |_key, items| items.size > 1 }.keys
        return if duplicate_skill_keys.empty?

        raise "Duplicate builtin skill keys detected in #{definition.key}: #{duplicate_skill_keys.join(", ")}"
      end
    end
  end
end
