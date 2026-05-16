# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::SolidQueueSchemaBootstrap do
  let(:db_config) { instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, schema_format: :ruby) }
  let(:configurations) { instance_double(ActiveRecord::DatabaseConfigurations) }
  let(:connection) { instance_spy(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:connection_pool) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool) }

  before do
    allow(ActiveRecord::Base).to receive(:configurations).and_return(configurations)
    allow(configurations).to receive(:configs_for).with(env_name: "test", name: "queue").and_return(db_config)
    allow(SolidQueue::Record).to receive(:connection_pool).and_return(connection_pool)
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:create)
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:load_schema)
  end

  it "accepts an array-shaped queue configuration result" do
    allow(configurations).to receive(:configs_for).with(env_name: "test", name: "queue").and_return([db_config])
    allow(connection_pool).to receive(:with_connection).and_yield(connection)
    allow(connection).to receive(:data_source_exists?)
      .with(described_class::QUEUE_TABLE_NAME)
      .and_return(true)

    described_class.ensure!

    expect(SolidQueue::Record).to have_received(:connection_pool)
  end

  it "does nothing when the queue schema is already present" do
    allow(connection_pool).to receive(:with_connection).and_yield(connection)
    allow(connection).to receive(:data_source_exists?)
      .with(described_class::QUEUE_TABLE_NAME)
      .and_return(true)

    described_class.ensure!

    expect(ActiveRecord::Tasks::DatabaseTasks).not_to have_received(:load_schema)
    expect(connection).not_to have_received(:execute)
  end

  it "loads the queue schema when the queue tables are missing" do
    allow(connection_pool).to receive(:with_connection).and_yield(connection)
    allow(connection).to receive(:data_source_exists?)
      .with(described_class::QUEUE_TABLE_NAME)
      .and_return(false, false)
    allow(connection).to receive(:execute)

    described_class.ensure!

    expect(connection).to have_received(:execute).with(
      "SELECT pg_advisory_lock(#{described_class::QUEUE_SCHEMA_LOCK_KEY})",
    )
    expect(ActiveRecord::Tasks::DatabaseTasks).to have_received(:load_schema).with(db_config, :ruby)
    expect(connection).to have_received(:execute).with(
      "SELECT pg_advisory_unlock(#{described_class::QUEUE_SCHEMA_LOCK_KEY})",
    )
  end

  it "skips loading after another process creates the queue tables under the advisory lock" do
    allow(connection_pool).to receive(:with_connection).and_yield(connection)
    allow(connection).to receive(:data_source_exists?)
      .with(described_class::QUEUE_TABLE_NAME)
      .and_return(false, true)
    allow(connection).to receive(:execute)

    described_class.ensure!

    expect(ActiveRecord::Tasks::DatabaseTasks).not_to have_received(:load_schema)
  end

  it "creates the queue database and retries when the queue connection is missing" do
    attempts = 0

    allow(connection_pool).to receive(:with_connection) do |&block|
      attempts += 1
      raise ActiveRecord::NoDatabaseError, "missing queue database" if attempts == 1

      block.call(connection)
    end
    allow(connection).to receive(:data_source_exists?)
      .with(described_class::QUEUE_TABLE_NAME)
      .and_return(true)

    described_class.ensure!

    expect(ActiveRecord::Tasks::DatabaseTasks).to have_received(:create).with(db_config)
  end

  it "ignores concurrent queue database creation races" do
    attempts = 0

    allow(connection_pool).to receive(:with_connection) do |&block|
      attempts += 1
      raise ActiveRecord::NoDatabaseError, "missing queue database" if attempts == 1

      block.call(connection)
    end
    allow(connection).to receive(:data_source_exists?)
      .with(described_class::QUEUE_TABLE_NAME)
      .and_return(true)
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:create)
      .with(db_config)
      .and_raise(ActiveRecord::DatabaseAlreadyExists, "already exists")

    expect { described_class.ensure! }.not_to raise_error
  end

  it "does nothing when there is no queue database configuration" do
    allow(configurations).to receive(:configs_for).with(env_name: "test", name: "queue").and_return(nil)

    described_class.ensure!

    expect(SolidQueue::Record).not_to have_received(:connection_pool)
  end
end
