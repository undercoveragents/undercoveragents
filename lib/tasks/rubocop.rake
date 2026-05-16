# frozen_string_literal: true

begin
  require "rubocop/rake_task"
rescue LoadError
  # RuboCop is only available in development and test.
end

if defined?(RuboCop::RakeTask)
  RuboCop::RakeTask.new(:rubocop) do |task|
    task.options = ["--parallel"]
  end
end
