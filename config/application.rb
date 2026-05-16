# frozen_string_literal: true

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../lib/undercover_agents/console_adapter_rails_compat"
require_relative "../lib/undercover_agents/action_cable_threaded_executor_compat"

module UndercoverAgents
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: ["assets", "tasks"])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Fiber isolation / request state
    # A fundamental configuration change needed for Falcon is setting Rails' internal isolation level from threads (default) to fibers. Without this, request state is shared per thread — and since Falcon runs every request on the same thread, all concurrent requests would share their state. Topenddevs You need something like this in your config:
    config.active_support.isolation_level = :fiber

    # ── Plugin System ──
    require "undercover_agents/plugin_system"
    UndercoverAgents::PluginSystem.load!(config, root.join("plugins"))
  end
end
