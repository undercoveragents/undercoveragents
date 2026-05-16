# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Default to S3-compatible object storage when bucket credentials are present.
  active_storage_service = ENV["ACTIVE_STORAGE_SERVICE"].presence
  active_storage_service ||= "s3" if ENV["ACTIVE_STORAGE_BUCKET"].present? || ENV["BUCKET"].present?
  config.active_storage.service = (active_storage_service.presence || "local").to_sym

  app_host = ENV["APP_HOST"].presence || ENV["RAILWAY_PUBLIC_DOMAIN"].presence || "undercoveragents.ai"
  app_protocol = ENV["APP_PROTOCOL"].presence || (app_host.present? ? "https" : nil)
  secure_transport = ENV.fetch("FORCE_SSL", app_protocol == "https" ? "true" : "false") == "true"
  mailer_from_address = ENV["MAILER_FROM_EMAIL"].presence || ENV["RESEND_FROM_EMAIL"].presence
  smtp_domain = ENV["RESEND_SMTP_DOMAIN"].presence
  smtp_domain ||= mailer_from_address.to_s[/@([^>]+)>?\z/, 1]
  smtp_domain ||= app_host || "localhost"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = secure_transport

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = secure_transport

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } } if secure_transport

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = true

  # Set host to be used by links generated in mailer templates.
  default_url_options = { host: app_host }
  default_url_options[:protocol] = app_protocol if app_protocol.present?
  config.action_mailer.default_url_options = default_url_options
  config.action_mailer.default_options = { from: mailer_from_address } if mailer_from_address.present?

  config.after_initialize do
    Rails.application.routes.default_url_options = default_url_options
  end

  # Deliver production mail through Resend SMTP using the same API key shown in the Resend dashboard.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: "smtp.resend.com",
    port: 587,
    domain: smtp_domain,
    user_name: "resend",
    password: ENV.fetch("RESEND_API_KEY", nil),
    authentication: :plain,
    enable_starttls_auto: true,
    open_timeout: 5,
    read_timeout: 5,
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
