# frozen_string_literal: true

require_relative "config/application"

Rails.application.load_tasks

if defined?(RSpec::Core::RakeTask)
  run_system_specs = ENV["SYSTEM_SPECS"] == "1"
  selected_specs = ENV.fetch("SPEC", nil)

  if !run_system_specs && selected_specs&.match?(%r{(?:^|[\s,])(?:spec/system/|plugins/.+/spec/system/)})
    abort "System specs are opt-in for rake. Re-run with SYSTEM_SPECS=1."
  end

  Rake::Task["default"].clear if Rake::Task.task_defined?("default")
  Rake::Task["spec"].clear
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = "{spec,plugins}/**/*_spec.rb"
    t.exclude_pattern = "{spec,plugins}/**/system/**/*_spec.rb" unless run_system_specs
  end
end

task default: ["lint", "spec"]
