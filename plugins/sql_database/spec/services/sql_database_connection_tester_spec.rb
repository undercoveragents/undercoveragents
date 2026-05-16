# frozen_string_literal: true

require "rails_helper"

RSpec.describe SqlDatabaseConnectionTester do
  describe "#call" do
    context "with PostgreSQL adapter" do
      let(:params) do
        {
          adapter_type: "postgresql",
          host: "localhost",
          port: 5432,
          database_name: "test_db",
          username: "user",
          encrypted_password: "pass",
        }
      end

      it "returns success when connection succeeds" do
        fake_conn = instance_double(PG::Connection)
        fake_result = [{ "version" => "PostgreSQL 16.0" }]
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:exec).with("SELECT version()").and_return(fake_result)
        allow(fake_conn).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(result.message).to eq("Connected successfully")
        expect(result.details[:version]).to eq("PostgreSQL 16.0")
      end

      it "returns failure when connection fails" do
        allow(PG).to receive(:connect).and_raise(PG::ConnectionBad.new("could not connect"))

        result = described_class.new(params).call

        expect(result.success?).to be(false)
        expect(result.message).to include("could not connect")
      end

      it "sanitizes passwords from error messages" do
        allow(PG).to receive(:connect).and_raise(
          PG::ConnectionBad.new("password=secret123 failed authentication"),
        )

        result = described_class.new(params).call

        expect(result.message).to include("password=[FILTERED]")
        expect(result.message).not_to include("secret123")
      end
    end

    context "with connection string" do
      let(:params) do
        {
          adapter_type: "postgresql",
          connection_string: "postgresql://user:pass@localhost:5432/test_db",
        }
      end

      it "connects using the connection string" do
        fake_conn = instance_double(PG::Connection)
        fake_result = [{ "version" => "PostgreSQL 16.0" }]
        allow(PG).to receive(:connect).with(params[:connection_string]).and_return(fake_conn)
        allow(fake_conn).to receive(:exec).with("SELECT version()").and_return(fake_result)
        allow(fake_conn).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
      end
    end

    context "with unsupported adapter" do
      let(:params) { { adapter_type: "oracle", host: "localhost" } }

      it "returns failure" do
        result = described_class.new(params).call

        expect(result.success?).to be(false)
        expect(result.message).to include("not yet supported")
      end
    end

    context "with PostgreSQL adapter database key" do
      let(:params) do
        {
          adapter_type: "postgresql",
          host: "localhost",
          port: 5432,
          database_name: "test_db",
          username: "user",
          encrypted_password: "pass",
        }
      end

      it "uses PG-specific keys (dbname, user) instead of generic keys" do
        fake_conn = instance_double(PG::Connection)
        fake_result = [{ "version" => "PostgreSQL 16.0" }]
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:exec).and_return(fake_result)
        allow(fake_conn).to receive(:close)

        described_class.new(params).call

        expect(PG).to have_received(:connect).with(hash_including(dbname: "test_db", user: "user"))
      end
    end

    context "with SSL enabled" do
      let(:params) do
        {
          adapter_type: "postgresql",
          host: "localhost",
          port: 5432,
          database_name: "test_db",
          ssl_enabled: true,
        }
      end

      it "includes sslmode in connection config" do
        fake_conn = instance_double(PG::Connection)
        fake_result = [{ "version" => "PostgreSQL 16.0" }]
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:exec).and_return(fake_result)
        allow(fake_conn).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(PG).to have_received(:connect).with(hash_including(sslmode: "require"))
      end
    end

    context "with default port" do
      let(:params) do
        {
          adapter_type: "postgresql",
          host: "localhost",
          database_name: "test_db",
        }
      end

      it "uses the default port for the adapter" do
        fake_conn = instance_double(PG::Connection)
        fake_result = [{ "version" => "PostgreSQL 16.0" }]
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:exec).and_return(fake_result)
        allow(fake_conn).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(PG).to have_received(:connect).with(hash_including(port: 5432))
      end
    end

    context "with MySQL adapter" do
      let(:params) do
        {
          adapter_type: "mysql",
          host: "localhost",
          port: 3306,
          database_name: "test_db",
          username: "user",
          encrypted_password: "pass",
        }
      end

      before do
        # mysql2 gem is not installed; stubbing require on all instances is the only way
        allow_any_instance_of(described_class).to receive(:require).with("mysql2").and_return(true) # rubocop:disable RSpec/AnyInstance
      end

      it "returns success when connection succeeds" do
        fake_client = double("Mysql2::Client") # rubocop:disable RSpec/VerifiedDoubles
        fake_result = [{ "version" => "8.0.35" }]
        mysql_klass = Class.new { def initialize(*_args, **_kwargs); end }
        stub_const("Mysql2::Client", mysql_klass)
        allow(Mysql2::Client).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:query).with("SELECT VERSION() AS version").and_return(fake_result)
        allow(fake_client).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(result.message).to eq("Connected successfully")
        expect(result.details[:version]).to eq("8.0.35")
      end

      it "returns failure when connection fails" do
        mysql_klass = Class.new { def initialize(*_args, **_kwargs); end }
        stub_const("Mysql2::Client", mysql_klass)
        allow(Mysql2::Client).to receive(:new).and_raise(StandardError.new("Access denied"))

        result = described_class.new(params).call

        expect(result.success?).to be(false)
        expect(result.message).to include("Access denied")
      end
    end

    context "with MySQL adapter and SSL enabled" do
      let(:params) do
        {
          adapter_type: "mysql",
          host: "localhost",
          port: 3306,
          database_name: "test_db",
          username: "user",
          encrypted_password: "pass",
          ssl_enabled: true,
        }
      end

      before do
        allow_any_instance_of(described_class).to receive(:require).with("mysql2").and_return(true) # rubocop:disable RSpec/AnyInstance
      end

      it "uses :required ssl_mode when ssl_enabled is true" do
        fake_client = double("Mysql2::Client") # rubocop:disable RSpec/VerifiedDoubles
        fake_result = [{ "version" => "8.0.35" }]
        mysql_klass = Class.new { def initialize(*_args, **_kwargs); end }
        stub_const("Mysql2::Client", mysql_klass)
        allow(Mysql2::Client).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:query).and_return(fake_result)
        allow(fake_client).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(Mysql2::Client).to have_received(:new).with(hash_including(ssl_mode: :required))
      end
    end

    context "with SQLite adapter" do
      let(:db_path) { Rails.root.join("tmp/test_conn.sqlite3").to_s }

      let(:params) do
        {
          adapter_type: "sqlite",
          database_name: db_path,
        }
      end

      before do
        # sqlite3 gem is not installed; stubbing require on all instances is the only way
        allow_any_instance_of(described_class).to receive(:require).with("sqlite3").and_return(true) # rubocop:disable RSpec/AnyInstance
      end

      it "returns success when database file exists" do
        FileUtils.touch(db_path)
        fake_db = double("SQLite3::Database") # rubocop:disable RSpec/VerifiedDoubles
        fake_exception_class = Class.new(StandardError)
        sqlite_db_klass = Class.new { def initialize(*_args); end }
        stub_const("SQLite3::Database", sqlite_db_klass)
        stub_const("SQLite3::Exception", fake_exception_class)
        allow(SQLite3::Database).to receive(:new).and_return(fake_db)
        allow(fake_db).to receive(:get_first_value).with("SELECT sqlite_version()").and_return("3.45.0")
        allow(fake_db).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(result.message).to eq("Connected successfully")
        expect(result.details[:version]).to eq("SQLite 3.45.0")
      ensure
        FileUtils.rm_f(db_path)
      end

      it "returns failure when database file does not exist" do
        fake_exception_class = Class.new(StandardError)
        stub_const("SQLite3::Exception", fake_exception_class)
        sqlite_db_klass = Class.new { def initialize(*_args); end }
        stub_const("SQLite3::Database", sqlite_db_klass)
        params_missing = { adapter_type: "sqlite", database_name: "/nonexistent/db.sqlite3" }

        result = described_class.new(params_missing).call

        expect(result.success?).to be(false)
        expect(result.message).to include("not found")
      end
    end

    context "with SSL enabled as string '1'" do
      let(:params) do
        {
          adapter_type: "postgresql",
          host: "localhost",
          port: 5432,
          database_name: "test_db",
          ssl_enabled: "1",
        }
      end

      it "includes sslmode in connection config" do
        fake_conn = instance_double(PG::Connection)
        fake_result = [{ "version" => "PostgreSQL 16.0" }]
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:exec).and_return(fake_result)
        allow(fake_conn).to receive(:close)

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(PG).to have_received(:connect).with(hash_including(sslmode: "require"))
      end
    end
  end

  describe "#available_databases" do
    context "with PostgreSQL adapter" do
      let(:params) do
        {
          adapter_type: "postgresql",
          host: "localhost",
          username: "user",
          encrypted_password: "pass",
        }
      end

      it "returns a discovered database list" do
        fake_conn = instance_double(PG::Connection)
        fake_result = instance_double(PG::Result, column_values: ["analytics", "warehouse"])
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:exec).with(described_class::POSTGRESQL_DATABASES_QUERY).and_return(fake_result)
        allow(fake_conn).to receive(:close)

        result = described_class.new(params).available_databases

        expect(result.success?).to be(true)
        expect(result.details[:databases]).to eq(["analytics", "warehouse"])
        expect(PG).to have_received(:connect).with(hash_including(dbname: "postgres", user: "user"))
      end

      it "returns failure when database discovery raises" do
        allow(PG).to receive(:connect).and_raise(PG::ConnectionBad.new("could not connect"))

        result = described_class.new(params).available_databases

        expect(result.success?).to be(false)
        expect(result.message).to include("could not connect")
      end
    end

    context "with MySQL adapter" do
      let(:params) do
        {
          adapter_type: "mysql",
          host: "localhost",
          username: "user",
          encrypted_password: "pass",
        }
      end

      before do
        allow_any_instance_of(described_class).to receive(:require).with("mysql2").and_return(true) # rubocop:disable RSpec/AnyInstance
      end

      it "returns a discovered database list" do
        fake_client = double("Mysql2::Client") # rubocop:disable RSpec/VerifiedDoubles
        mysql_klass = Class.new { def initialize(*_args, **_kwargs); end }
        stub_const("Mysql2::Client", mysql_klass)
        allow(Mysql2::Client).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:query).with(described_class::MYSQL_DATABASES_QUERY).and_return(
          [
            { "Database" => "analytics" },
            { "Database" => "warehouse" },
          ],
        )
        allow(fake_client).to receive(:close)

        result = described_class.new(params).available_databases

        expect(result.success?).to be(true)
        expect(result.details[:databases]).to eq(["analytics", "warehouse"])
      end
    end

    context "with SQLite adapter" do
      it "returns a manual-entry message" do
        result = described_class.new(adapter_type: "sqlite").available_databases

        expect(result.success?).to be(false)
        expect(result.message).to include("manual")
      end
    end

    context "with unsupported adapter" do
      it "returns a not-supported message" do
        result = described_class.new(adapter_type: "oracle").available_databases

        expect(result.success?).to be(false)
        expect(result.message).to include("not yet supported")
      end
    end
  end
end
