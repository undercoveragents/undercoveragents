# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SchemaDiscoverer do
  let(:sql_database) do
    create(:connectors_sql_database,
           adapter_type: "postgresql",
           host: "localhost",
           port: 5432,
           database_name: "test_db",
           schema_name: "public",
           username: "user",
           encrypted_password: "pass",)
  end

  describe "#call" do
    context "with PostgreSQL adapter" do
      let(:fake_conn) { instance_double(PG::Connection) }

      let(:tables_result) { [{ "table_name" => "users" }] }
      let(:table_columns) do
        [{ "column_name" => "id", "data_type" => "integer", "is_nullable" => "NO", "column_default" => nil }]
      end
      let(:views_result) { [{ "table_name" => "active_users" }] }
      let(:view_columns) do
        [{ "column_name" => "name", "data_type" => "text", "is_nullable" => "YES", "column_default" => nil }]
      end
      let(:matviews_result) { [{ "name" => "user_stats" }] }
      let(:matview_columns) { [{ "column_name" => "total", "data_type" => "bigint", "nullable" => "t" }] }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec_params).with(anything, ["public"]).and_return(
          tables_result, views_result, matviews_result,
        )
        allow(fake_conn).to receive(:exec_params).with(anything, ["public", "users"]).and_return(table_columns)
        allow(fake_conn).to receive(:exec_params).with(anything, ["public", "active_users"]).and_return(view_columns)
        allow(fake_conn).to receive(:exec_params).with(anything, ["public", "user_stats"]).and_return(matview_columns)
      end

      it "returns success with discovered objects" do
        result = described_class.new(sql_database).call

        expect(result.success?).to be(true)
        expect(result.schema["objects"].size).to eq(3)
      end

      it "discovers tables with columns" do
        result = described_class.new(sql_database).call
        table = result.schema["objects"].find { |o| o["type"] == "table" }

        expect(table["name"]).to eq("users")
        expect(table["columns"].first["name"]).to eq("id")
        expect(table["columns"].first["nullable"]).to be(false)
      end

      it "discovers views with columns" do
        result = described_class.new(sql_database).call
        view = result.schema["objects"].find { |o| o["type"] == "view" }

        expect(view["name"]).to eq("active_users")
        expect(view["columns"].first["name"]).to eq("name")
        expect(view["columns"].first["nullable"]).to be(true)
      end

      it "discovers materialized views with columns" do
        result = described_class.new(sql_database).call
        matview = result.schema["objects"].find { |o| o["type"] == "materialized_view" }

        expect(matview["name"]).to eq("user_stats")
        expect(matview["columns"].first["name"]).to eq("total")
        expect(matview["columns"].first["nullable"]).to be(true)
      end

      it "returns failure when connection fails" do
        allow(PG).to receive(:connect).and_raise(PG::ConnectionBad.new("could not connect"))

        result = described_class.new(sql_database).call

        expect(result.success?).to be(false)
        expect(result.message).to include("failed")
      end
    end

    context "with unsupported adapter" do
      let(:sql_database) do
        create(:connectors_sql_database,
               adapter_type: "oracle",
               host: "localhost",
               database_name: "test_db",
               schema_name: "public",)
      end

      it "returns failure" do
        result = described_class.new(sql_database).call

        expect(result.success?).to be(false)
        expect(result.message).to include("not supported")
      end
    end

    context "with connection string" do
      let(:sql_database) do
        create(:connectors_sql_database,
               adapter_type: "postgresql",
               host: "localhost",
               database_name: "test_db",
               schema_name: "public",
               connection_string: "postgresql://user:pass@localhost:5432/test_db",)
      end

      it "connects using the connection string" do
        fake_conn = instance_double(PG::Connection)
        allow(PG).to receive(:connect).with(sql_database.connection_string).and_return(fake_conn)
        allow(fake_conn).to receive(:exec_params).and_return([])
        allow(fake_conn).to receive(:close)

        result = described_class.new(sql_database).call

        expect(result.success?).to be(true)
        expect(PG).to have_received(:connect).with(sql_database.connection_string)
      end
    end

    context "with MySQL adapter" do
      let(:sql_database) do
        create(:connectors_sql_database,
               adapter_type: "mysql",
               host: "localhost",
               port: 3306,
               database_name: "test_db",
               schema_name: "public",)
      end

      it "delegates to the MySQL discoverer" do
        fake_client = double("Mysql2::Client") # rubocop:disable RSpec/VerifiedDoubles
        mysql_klass = Class.new { def initialize(**_kwargs); end }
        stub_const("Mysql2::Client", mysql_klass)
        allow(Mysql2::Client).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:escape) { |s| s }
        allow(fake_client).to receive(:query).and_return([], [])
        allow(fake_client).to receive(:close)
        # mysql2 gem is not installed; stubbing require on all instances is the only way
        allow_any_instance_of(Tools::Discoverers::Mysql).to receive(:require).with("mysql2").and_return(true) # rubocop:disable RSpec/AnyInstance

        result = described_class.new(sql_database).call

        expect(result.success?).to be(true)
      end
    end

    context "with SQLite adapter" do
      let(:db_path) { "/tmp/test_discoverer.sqlite3" }

      let(:sql_database) do
        create(:connectors_sql_database,
               adapter_type: "sqlite",
               host: "localhost",
               database_name: db_path,
               schema_name: "public",)
      end

      it "delegates to the SQLite discoverer" do
        fake_exception_class = Class.new(StandardError)
        stub_const("SQLite3::Exception", fake_exception_class)
        sqlite_db_klass = Class.new { def initialize(*_args); end }
        stub_const("SQLite3::Database", sqlite_db_klass)
        fake_db = double("SQLite3::Database") # rubocop:disable RSpec/VerifiedDoubles
        allow(SQLite3::Database).to receive(:new).and_return(fake_db)
        allow(fake_db).to receive(:results_as_hash=)
        allow(fake_db).to receive(:execute).and_return([])
        allow(fake_db).to receive(:close)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(db_path).and_return(true)
        # sqlite3 gem is not installed; stubbing require on all instances is the only way
        allow_any_instance_of(Tools::Discoverers::Sqlite).to receive(:require).with("sqlite3").and_return(true) # rubocop:disable RSpec/AnyInstance

        result = described_class.new(sql_database).call

        expect(result.success?).to be(true)
        expect(result.schema["objects"]).to be_an(Array)
      end
    end

    context "when an error occurs during discovery" do
      it "sanitizes password from error messages" do
        allow(PG).to receive(:connect).and_raise(
          PG::ConnectionBad.new("password=secret123 connection://user:pass@host"),
        )

        result = described_class.new(sql_database).call

        expect(result.success?).to be(false)
        expect(result.message).not_to include("secret123")
        expect(result.message).to include("[FILTERED]")
      end
    end
  end
end
