# frozen_string_literal: true

rake_task = defined?(Rake.application) && Rake.application.top_level_tasks.any?

return unless Rails.env.production?
return if rake_task
return if ENV.fetch("SENTRY_DSN", "").strip.empty?

Sentry.init do |config|
  config.dsn = ENV.fetch("SENTRY_DSN")
  config.traces_sample_rate = 0.01
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
end
