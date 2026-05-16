# frozen_string_literal: true

Rails.application.config.after_initialize do
  rake_tasks = defined?(Rake.application) ? Rake.application.top_level_tasks : []
  asset_task = rake_tasks.any? { |task| task.start_with?("assets:") }
  db_task = rake_tasks.any? { |task| task.start_with?("db:") }

  next if Rails.env.test? || asset_task || db_task

  log_skip = lambda do |error|
    Rails.logger.debug { "[BuiltinSkills] Skipping startup sync: #{error.message}" } if defined?(Rails.logger)
  end

  begin
    BuiltinSkills::Synchronizer.ensure_present!
  rescue ActiveRecord::StatementInvalid => e
    log_skip.call(e)
  end
end
