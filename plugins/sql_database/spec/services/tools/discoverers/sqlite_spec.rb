# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Discoverers::Sqlite do
  let(:sql_database) do
    build(:connectors_sql_database,
          adapter_type: "sqlite",
          database_name: db_path,
          host: "localhost",)
  end

  let(:db_path) { "/tmp/test_discovery.sqlite3" }

  describe "#discover" do
    let(:fake_db) { double("SQLite3::Database") } # rubocop:disable RSpec/VerifiedDoubles

    before do
      fake_exception_class = Class.new(StandardError)
      stub_const("SQLite3::Exception", fake_exception_class)
      sqlite_db_klass = Class.new { def initialize(*_args); end }
      stub_const("SQLite3::Database", sqlite_db_klass)
      allow(SQLite3::Database).to receive(:new).and_return(fake_db)
      allow(fake_db).to receive(:results_as_hash=)
      allow(fake_db).to receive(:close)
      # sqlite3 gem is not installed; stubbing require on all instances is the only way
      allow_any_instance_of(described_class).to receive(:require).with("sqlite3").and_return(true) # rubocop:disable RSpec/AnyInstance
    end

    context "when database file exists" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(db_path).and_return(true)
      end

      it "discovers tables" do
        tables = [{ "name" => "users" }]
        columns = [
          { "name" => "id", "type" => "INTEGER", "notnull" => 1 },
          { "name" => "email", "type" => "TEXT", "notnull" => 0 },
        ]

        allow(fake_db).to receive(:execute)
          .with("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
          .and_return(tables)
        allow(fake_db).to receive(:execute)
          .with("SELECT name FROM sqlite_master WHERE type='view' ORDER BY name")
          .and_return([])
        allow(fake_db).to receive(:execute)
          .with("PRAGMA table_info('users')")
          .and_return(columns)

        objects = described_class.new(sql_database).discover

        tables_found = objects.select { |o| o["type"] == "table" }
        expect(tables_found.pluck("name")).to include("users")
        expect(tables_found.first["columns"].size).to eq(2)
      end

      it "discovers views" do
        views = [{ "name" => "active_users" }]
        view_columns = [{ "name" => "id", "type" => "INTEGER", "notnull" => 1 }]

        allow(fake_db).to receive(:execute)
          .with("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
          .and_return([])
        allow(fake_db).to receive(:execute)
          .with("SELECT name FROM sqlite_master WHERE type='view' ORDER BY name")
          .and_return(views)
        allow(fake_db).to receive(:execute)
          .with("PRAGMA table_info('active_users')")
          .and_return(view_columns)

        objects = described_class.new(sql_database).discover

        view_objs = objects.select { |o| o["type"] == "view" }
        expect(view_objs.pluck("name")).to include("active_users")
      end

      it "detects nullable columns" do
        columns = [
          { "name" => "name", "type" => "TEXT", "notnull" => 1 },
          { "name" => "email", "type" => "TEXT", "notnull" => 0 },
        ]

        allow(fake_db).to receive(:execute)
          .with("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
          .and_return([{ "name" => "users" }])
        allow(fake_db).to receive(:execute)
          .with("SELECT name FROM sqlite_master WHERE type='view' ORDER BY name")
          .and_return([])
        allow(fake_db).to receive(:execute)
          .with("PRAGMA table_info('users')")
          .and_return(columns)

        objects = described_class.new(sql_database).discover
        users = objects.find { |o| o["name"] == "users" }

        name_col = users["columns"].find { |c| c["name"] == "name" }
        email_col = users["columns"].find { |c| c["name"] == "email" }

        expect(name_col["nullable"]).to be(false)
        expect(email_col["nullable"]).to be(true)
      end
    end

    context "when database file does not exist" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(db_path).and_return(false)
      end

      it "raises an error" do
        expect do
          described_class.new(sql_database).discover
        end.to raise_error(SQLite3::Exception, /not found/)
      end
    end
  end
end
