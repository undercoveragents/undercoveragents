# frozen_string_literal: true

module Skills
  class SpecificationValidator
    NAME_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    def initialize(name:, description:, compatibility: nil, directory_name: nil)
      @name = name.to_s.strip
      @description = description.to_s.strip
      @compatibility = compatibility.to_s.strip
      @directory_name = directory_name.to_s.strip
    end

    def warnings
      [].tap do |messages|
        add_name_warnings(messages)
        add_length_warnings(messages)
        add_directory_warning(messages)
      end
    end

    private

    def add_name_warnings(messages)
      if @name.blank?
        messages << "The skill is missing a name."
      elsif !NAME_FORMAT.match?(@name)
        messages << "The skill name should use lowercase letters, numbers, and single hyphens only."
      end
    end

    def add_length_warnings(messages)
      messages << "The skill name exceeds the Agent Skills recommendation of 64 characters." if @name.length > 64
      if @description.length > 1024
        messages << "The description exceeds the Agent Skills recommendation of 1024 characters."
      end

      return unless @compatibility.length > 500

      messages << "The compatibility note exceeds the Agent Skills recommendation of 500 characters."
    end

    def add_directory_warning(messages)
      return unless @directory_name.present? && @name.present? && @directory_name != @name

      messages << "The imported directory name does not match the skill name frontmatter."
    end
  end
end
