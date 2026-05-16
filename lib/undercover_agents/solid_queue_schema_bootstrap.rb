# frozen_string_literal: true

module UndercoverAgents
  module SolidQueueSchemaBootstrap
    extend self

    QUEUE_TABLE_NAME = "solid_queue_jobs"
    QUEUE_SCHEMA_LOCK_KEY = 52_104_042_001

    def ensure!
      db_config = queue_db_config
      return unless db_config

      with_queue_connection(db_config) do |connection|
        return if connection.data_source_exists?(QUEUE_TABLE_NAME)

        connection.execute("SELECT pg_advisory_lock(#{QUEUE_SCHEMA_LOCK_KEY})")

        begin
          return if connection.data_source_exists?(QUEUE_TABLE_NAME)

          ActiveRecord::Tasks::DatabaseTasks.load_schema(db_config, db_config.schema_format)
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{QUEUE_SCHEMA_LOCK_KEY})")
        end
      end
    end

    private

    def queue_db_config
      Array.wrap(ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "queue")).first
    end

    def with_queue_connection(db_config, &)
      SolidQueue::Record.connection_pool.with_connection(&)
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
      create_queue_database!(db_config)
      retry
    end

    def create_queue_database!(db_config)
      ActiveRecord::Tasks::DatabaseTasks.create(db_config)
    rescue ActiveRecord::DatabaseAlreadyExists
      nil
    end
  end
end
