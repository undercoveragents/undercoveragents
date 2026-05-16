# frozen_string_literal: true

require "rails_helper"

RSpec.describe SqlConnectionConfigBuilder do
  subject(:builder) { host_class.new }

  let(:host_class) do
    Class.new do
      include SqlConnectionConfigBuilder

      def connect(config)
        connect_pg(config)
      end
    end
  end

  describe "#build_pg_config_for" do
    let(:sql_database) do
      instance_double(
        Connectors::SqlDatabase,
        connection_string?: true,
        connection_string: "postgresql://user:pass@host/db",
        host: "db-host",
        effective_port: 5432,
        database_name: "analytics",
        username: "app",
        encrypted_password: "secret",
        ssl_enabled?: true,
      )
    end

    it "returns URL and discrete fallback fields" do
      config = builder.send(:build_pg_config_for, sql_database)

      expect(config).to include(
        url: "postgresql://user:pass@host/db",
        host: "db-host",
        port: 5432,
        dbname: "analytics",
        user: "app",
        password: "secret",
        sslmode: "require",
      )
    end

    it "omits url and sslmode when they are not configured" do
      plain_sql_database = instance_double(
        Connectors::SqlDatabase,
        connection_string?: false,
        host: "db-host",
        effective_port: 5432,
        database_name: "analytics",
        username: "app",
        encrypted_password: "secret",
        ssl_enabled?: false,
      )

      config = builder.send(:build_pg_config_for, plain_sql_database)

      expect(config).not_to have_key(:url)
      expect(config).not_to have_key(:sslmode)
    end
  end

  describe "#connect_pg" do
    it "uses keyword params when url is absent" do
      allow(PG).to receive(:connect).with(host: "localhost", dbname: "db").and_return(:conn)

      result = builder.connect(host: "localhost", dbname: "db")

      expect(result).to eq(:conn)
    end

    it "uses URL connection when it succeeds" do
      allow(PG).to receive(:connect).with("postgresql://ok").and_return(:conn)

      result = builder.connect(url: "postgresql://ok")

      expect(result).to eq(:conn)
    end

    it "falls back to keyword params when URL raises 'string not matched'" do
      allow(PG).to receive(:connect).with("postgresql://bad uri").and_raise(ArgumentError, "string not matched")
      allow(PG).to receive(:connect).with(host: "localhost", dbname: "db").and_return(:conn)

      result = builder.connect(url: "postgresql://bad uri", host: "localhost", dbname: "db")

      expect(result).to eq(:conn)
    end

    it "re-raises non matching errors" do
      allow(PG).to receive(:connect).with("postgresql://bad").and_raise(ArgumentError, "invalid uri")

      expect do
        builder.connect(url: "postgresql://bad", host: "localhost", dbname: "db")
      end.to raise_error(ArgumentError, "invalid uri")
    end

    it "re-raises when fallback config is empty" do
      allow(PG).to receive(:connect).with("postgresql://bad").and_raise(ArgumentError, "string not matched")

      expect do
        builder.connect(url: "postgresql://bad")
      end.to raise_error(ArgumentError, "string not matched")
    end
  end
end
