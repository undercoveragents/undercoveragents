# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ConnectionConfigBuilder do
  let(:test_class) do
    Class.new do
      include Tools::ConnectionConfigBuilder

      public :build_pg_config_for, :build_mysql_config_for
    end
  end

  let(:instance) { test_class.new }

  describe "#build_pg_config_for" do
    let(:sql_database) do
      build(:connectors_sql_database,
            host: "dbhost", port: 5432, database_name: "mydb",
            username: "user", encrypted_password: "pass",
            ssl_enabled: false, connection_string: nil,)
    end

    it "builds host, port, and dbname from fields" do
      config = instance.build_pg_config_for(sql_database)

      expect(config[:host]).to eq("dbhost")
      expect(config[:port]).to eq(5432)
      expect(config[:dbname]).to eq("mydb")
    end

    it "builds user, password, and timeout from fields" do
      config = instance.build_pg_config_for(sql_database)

      expect(config[:user]).to eq("user")
      expect(config[:password]).to eq("pass")
      expect(config[:connect_timeout]).to eq(10)
    end

    it "does not include sslmode when SSL is disabled" do
      config = instance.build_pg_config_for(sql_database)

      expect(config).not_to have_key(:sslmode)
    end

    it "includes sslmode when SSL is enabled" do
      sql_database = build(:connectors_sql_database, ssl_enabled: true, connection_string: nil)

      config = instance.build_pg_config_for(sql_database)

      expect(config[:sslmode]).to eq("require")
    end

    it "returns URL config when connection string is present" do
      sql_database = build(:connectors_sql_database,
                           connection_string: "postgresql://user:pass@localhost/mydb",)

      config = instance.build_pg_config_for(sql_database)

      expect(config).to eq({ url: "postgresql://user:pass@localhost/mydb" })
    end

    it "compacts nil values" do
      sql_database = build(:connectors_sql_database,
                           username: nil, encrypted_password: nil,
                           connection_string: nil,)

      config = instance.build_pg_config_for(sql_database)

      expect(config).not_to have_key(:user)
      expect(config).not_to have_key(:password)
    end
  end

  describe "#build_mysql_config_for" do
    let(:sql_database) do
      build(:connectors_sql_database,
            adapter_type: "mysql",
            host: "dbhost", port: 3306, database_name: "mydb",
            username: "user", encrypted_password: "pass",
            connection_string: nil,)
    end

    it "builds host, port, and database from fields" do
      config = instance.build_mysql_config_for(sql_database)

      expect(config[:host]).to eq("dbhost")
      expect(config[:port]).to eq(3306)
      expect(config[:database]).to eq("mydb")
    end

    it "builds username, password, and timeout from fields" do
      config = instance.build_mysql_config_for(sql_database)

      expect(config[:username]).to eq("user")
      expect(config[:password]).to eq("pass")
      expect(config[:connect_timeout]).to eq(10)
    end

    it "returns URL config when connection string is present" do
      sql_database = build(:connectors_sql_database,
                           adapter_type: "mysql",
                           connection_string: "mysql2://user:pass@localhost/mydb",)

      config = instance.build_mysql_config_for(sql_database)

      expect(config).to eq({ url: "mysql2://user:pass@localhost/mydb" })
    end
  end
end
