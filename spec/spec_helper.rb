# frozen_string_literal: true

Warning[:experimental] = false

require_relative "default_spec_discovery"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  # Exclude system tests by default.
  config.filter_run_excluding js: true unless ENV["SYSTEM_SPECS"] == "1"
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.order = :random
  config.profile_examples = 10

  config.default_formatter = "doc" if config.files_to_run.one?

  Kernel.srand config.seed
end
