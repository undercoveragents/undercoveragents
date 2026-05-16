# frozen_string_literal: true

require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch
  minimum_coverage line: 100, branch: 100

  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"
  add_filter "/tmp/"
  add_filter "/lib/builtin_tools/"
  add_filter "/lib/undercover_agents/ruby_llm_debug_logging.rb"

  add_group "Services", "/app/services"
  add_group "Policies", "/app/policies"
  add_group "Tools", "/app/tools"
  add_group "Agents", "/app/agents"
  add_group "Presenters", "/app/presenters"
  add_group "Types", "/app/types"
  add_group "Validators", "/app/validators"
  add_group "Plugins", "/plugins/"
end

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?

# Suppress Falcon/Console gem JSON log output (process_action, etc.) during tests.
# Console uses its own logging pipeline that bypasses Rails config.log_level.
# Set to FATAL so that error/warn entries emitted by expected error paths don't
# bleed into the test progress output.
Console.logger.level = Console::Logger::FATAL
require "rspec/rails"
require "capybara/rspec"
require "webmock/rspec"

# Load all support files
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot
  config.include FactoryBot::Syntax::Methods

  # Shoulda Matchers
  config.include Shoulda::Matchers::ActiveModel, type: :model
  config.include Shoulda::Matchers::ActiveRecord, type: :model

  config.before(:suite) do
    TestDatabaseIsolation.truncate_all!
  end

  config.around do |example|
    Current.reset
    example.run
  ensure
    Current.reset
  end

  config.around(:each, :commit_db) do |example|
    example.run
  ensure
    TestDatabaseIsolation.truncate_all!
  end

  config.around(:each, :js, type: :system) do |example|
    example.run
  ensure
    TestDatabaseIsolation.truncate_all!
  end

  config.after(:suite) do
    TestDatabaseIsolation.truncate_all!
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# WebMock: disable external requests by default
WebMock.disable_net_connect!(allow_localhost: true)

plugin_factory_paths = Rails.root.glob("plugins/**/spec/factories").map(&:to_s)
FactoryBot.definition_file_paths = (FactoryBot.definition_file_paths + plugin_factory_paths).uniq
FactoryBot.reload
