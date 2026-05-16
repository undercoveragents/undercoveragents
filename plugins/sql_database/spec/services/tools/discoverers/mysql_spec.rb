# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Discoverers::Mysql do
  let(:sql_database) do
    build(:connectors_sql_database,
          adapter_type: "mysql",
          host: "localhost",
          port: 3306,
          database_name: "test_db",
          username: "user",
          encrypted_password: "pass",)
  end

  describe "#discover" do
    let(:fake_client) { double("Mysql2::Client") } # rubocop:disable RSpec/VerifiedDoubles

    before do
      mysql_klass = Class.new { def initialize(**_kwargs); end }
      stub_const("Mysql2::Client", mysql_klass)
      allow(Mysql2::Client).to receive(:new).and_return(fake_client)
      allow(fake_client).to receive(:close)
      # mysql2 gem is not installed; stubbing require on all instances is the only way
      allow_any_instance_of(described_class).to receive(:require).with("mysql2").and_return(true) # rubocop:disable RSpec/AnyInstance
    end

    it "discovers table names" do
      tables_result = [{ "table_name" => "users" }]
      columns_result = [
        { "column_name" => "id", "data_type" => "int", "is_nullable" => "NO", "column_default" => nil },
        { "column_name" => "email", "data_type" => "varchar", "is_nullable" => "YES", "column_default" => nil },
      ]

      allow(fake_client).to receive(:escape) { |s| s }
      allow(fake_client).to receive(:query).and_return(tables_result, columns_result, [], [])

      objects = described_class.new(sql_database).discover

      expect(objects.size).to eq(1)
      expect(objects.first["name"]).to eq("users")
      expect(objects.first["type"]).to eq("table")
    end

    it "discovers table columns" do
      tables_result = [{ "table_name" => "users" }]
      columns_result = [
        { "column_name" => "id", "data_type" => "int", "is_nullable" => "NO", "column_default" => nil },
        { "column_name" => "email", "data_type" => "varchar", "is_nullable" => "YES", "column_default" => nil },
      ]

      allow(fake_client).to receive(:escape) { |s| s }
      allow(fake_client).to receive(:query).and_return(tables_result, columns_result, [], [])

      objects = described_class.new(sql_database).discover

      expect(objects.first["columns"].size).to eq(2)
      expect(objects.first["columns"].first["name"]).to eq("id")
      expect(objects.first["columns"].first["nullable"]).to be(false)
    end

    it "discovers views" do
      views_result = [{ "table_name" => "active_users_view" }]
      view_columns = [
        { "column_name" => "id", "data_type" => "int", "is_nullable" => "NO", "column_default" => nil },
      ]

      allow(fake_client).to receive(:escape) { |s| s }
      allow(fake_client).to receive(:query).and_return([], views_result, view_columns)

      objects = described_class.new(sql_database).discover

      expect(objects.size).to eq(1)
      expect(objects.first["type"]).to eq("view")
      expect(objects.first["name"]).to eq("active_users_view")
    end

    it "handles uppercase column names from MySQL" do
      tables_result = [{ "TABLE_NAME" => "products" }]
      columns_result = [
        { "COLUMN_NAME" => "id", "DATA_TYPE" => "int", "IS_NULLABLE" => "NO", "COLUMN_DEFAULT" => nil },
      ]

      allow(fake_client).to receive(:escape) { |s| s }
      allow(fake_client).to receive(:query).and_return(tables_result, columns_result, [], [])

      objects = described_class.new(sql_database).discover

      expect(objects.first["name"]).to eq("products")
      expect(objects.first["columns"].first["name"]).to eq("id")
    end

    it "returns empty array when no objects found" do
      allow(fake_client).to receive(:escape) { |s| s }
      allow(fake_client).to receive(:query).and_return([], [])

      objects = described_class.new(sql_database).discover

      expect(objects).to eq([])
    end

    it "uses connection string when available" do
      sql_database.connection_string = "mysql2://user:pass@localhost/test_db"

      allow(fake_client).to receive(:escape) { |s| s }
      allow(fake_client).to receive(:query).and_return([], [])

      described_class.new(sql_database).discover

      expect(Mysql2::Client).to have_received(:new).with(hash_not_including(:host))
    end
  end
end
