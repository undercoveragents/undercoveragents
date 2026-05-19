# frozen_string_literal: true

source "https://rubygems.org"

# Core
gem "bootsnap", require: false
gem "importmap-rails"
gem "pg", "~> 1.1"
gem "propshaft"
gem "rails", "~> 8.1.2"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "turbo-rails"

# Application server
gem "falcon-rails"

# Views
gem "haml-rails"
gem "simple_form"

# Background jobs & caching
gem "mission_control-jobs"
gem "solid_cache"
gem "solid_queue"

# Deployment
gem "kamal", require: false
gem "thruster", require: false

# Image processing
gem "aws-sdk-s3", require: false
gem "image_processing", "~> 1.2"
gem "ruby-vips"

# Windows timezone data
gem "tzinfo-data", platforms: [:windows, :jruby]

gem "ruby_llm"
gem "rubyzip"
gem "toml-rb"

# MCP (Model Context Protocol) client
gem "ruby_llm-mcp"

# Deep cloning
gem "amoeba"

# Expression evaluation
gem "dentaku"

# Search / filtering
gem "ransack"

# Authentication
gem "bcrypt", "~> 3.1"
gem "omniauth"
gem "omniauth-google-oauth2"
gem "omniauth-keycloak"
gem "omniauth-rails_csrf_protection"

# Authorization
gem "pundit"

# Friendly URLs
gem "friendly_id", "~> 5.5"

# Charts & data grouping
gem "chartkick"
gem "groupdate"

# Rich text editor
gem "lexxy", "~> 0.1.26.beta"

# API documentation
gem "rswag-api"
gem "rswag-ui"

# Error tracking
gem "sentry-rails"
gem "sentry-ruby"

# Pagination
gem "pagy", "~> 43.3"

# Plugin-owned gem dependencies
Dir.glob(File.expand_path("plugins/*/Gemfile", __dir__)).each do |plugin_gemfile|
  eval_gemfile plugin_gemfile
end

group :development, :test do
  # Debugging
  gem "debug", platforms: [:mri, :windows], require: "debug/prelude"

  # Testing
  gem "factory_bot_rails"
  gem "faker"
  gem "rspec-rails"
  gem "shoulda-matchers"

  # Linting & static analysis
  gem "haml_lint", require: false
  gem "rubocop", require: false
  gem "rubocop-capybara", require: false
  gem "rubocop-factory_bot", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rake", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rspec_rails", require: false

  # Security
  gem "brakeman", require: false
  gem "bundler-audit", require: false

  # Environment
  gem "dotenv-rails"
end

group :development do
  gem "web-console"

  # Email preview
  gem "letter_opener_web"

  # Better error pages
  gem "better_errors"
  gem "binding_of_caller"

  # N+1 query detection
  gem "bullet"

  # Annotate models with schema info
  gem "annotaterb"

  # ERB -> Haml conversion
  gem "erb2haml"
end

group :test do
  # Integration testing
  gem "capybara"
  gem "selenium-webdriver"

  # Code coverage
  gem "simplecov", require: false
  gem "simplecov-cobertura", require: false

  # Time travel
  gem "timecop"

  # HTTP mocking
  gem "vcr"
  gem "webmock"
end
