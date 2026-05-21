# frozen_string_literal: true

module UndercoverAgents
  module RSpecDefaultSpecDiscovery
    ROOT = File.expand_path("..", __dir__)
    DEFAULT_GLOBS = [
      File.join(ROOT, "spec/**/*_spec.rb"),
      File.join(ROOT, "plugins/**/spec/**/*_spec.rb"),
    ].freeze

    def files_to_run
      paths = instance_variable_get(:@files_or_directories_to_run)
      return super unless default_suite_invocation?(paths)

      @files_to_run = Dir[*DEFAULT_GLOBS].sort
    end

    private

    def default_suite_invocation?(paths)
      paths == [default_path] && !explicit_spec_path_argument?
    end

    def explicit_spec_path_argument?
      ARGV.any? do |arg|
        candidate = arg.to_s.split(":", 2).first
        next false if candidate.empty? || candidate.start_with?("-")

        expanded = File.expand_path(candidate, ROOT)
        next false unless File.exist?(expanded)

        expanded == File.join(ROOT, default_path) ||
          expanded.start_with?(File.join(ROOT, "spec/")) ||
          expanded.start_with?(File.join(ROOT, "plugins/"))
      end
    end
  end
end

RSpec::Core::Configuration.prepend(UndercoverAgents::RSpecDefaultSpecDiscovery)
