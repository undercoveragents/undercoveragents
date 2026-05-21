# frozen_string_literal: true

require_relative "config/application"

Rails.application.load_tasks

if defined?(RSpec::Core::RakeTask)
  Rake::Task["default"].clear if Rake::Task.task_defined?("default")
  Rake::Task["spec"].clear
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = "{spec,plugins}/**/*_spec.rb"
  end
end

task default: ["lint", "spec"]
