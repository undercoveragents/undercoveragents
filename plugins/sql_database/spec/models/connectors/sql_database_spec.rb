# frozen_string_literal: true

# == Schema Information
#
# Table name: connectors
# Database name: primary
#
#  id             :bigint           not null, primary key
#  configuration  :jsonb            not null
#  connector_type :string           not null
#  description    :text
#  enabled        :boolean          default(FALSE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_connectors_on_connector_type           (connector_type)
#  index_connectors_on_enabled                  (enabled)
#  index_connectors_on_name                     (name) UNIQUE
#  index_connectors_on_slug                     (slug) UNIQUE
#  index_connectors_on_telegram_webhook_secret  (((configuration ->> 'webhook_secret'::text))) UNIQUE WHERE (((connector_type)::text = 'telegram'::text) AND ((configuration ->> 'webhook_secret'::text) IS NOT NULL))
#
require "rails_helper"

RSpec.describe Connectors::SqlDatabase do
  subject(:sql_database) { build(:connectors_sql_database) }

  describe "list_resources metadata" do
    it "declares the connector kind" do
      expect(described_class.list_resources_kind).to eq("sql_database_connectors")
      expect(described_class.list_resources_title).to eq("SQL Database Connectors")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:adapter_type) }
    it { is_expected.to validate_inclusion_of(:adapter_type).in_array(described_class::ADAPTER_TYPES) }
    it { is_expected.to validate_presence_of(:schema_name) }

    it "rejects pool_size outside valid range" do
      sql_database.pool_size = 0
      expect(sql_database).not_to be_valid
      expect(sql_database.errors[:pool_size]).to be_present
    end

    it "rejects timeout outside valid range" do
      sql_database.timeout = 0
      expect(sql_database).not_to be_valid
      expect(sql_database.errors[:timeout]).to be_present
    end

    it "rejects max_results outside valid range" do
      sql_database.max_results = 0
      expect(sql_database).not_to be_valid
      expect(sql_database.errors[:max_results]).to be_present
    end

    context "without a connection string" do
      subject { build(:connectors_sql_database, connection_string: nil) }

      it { is_expected.to validate_presence_of(:host) }
      it { is_expected.to validate_presence_of(:database_name) }
    end

    context "with a connection string" do
      subject { build(:connectors_sql_database, connection_string: "postgresql://localhost/test") }

      it { is_expected.not_to validate_presence_of(:host) }
      it { is_expected.not_to validate_presence_of(:database_name) }
    end
  end

  describe "defaults" do
    it "defaults host to localhost" do
      expect(described_class.new.host).to eq("localhost")
    end
  end

  describe "#default_port" do
    it "returns 5432 for postgresql" do
      db = build(:connectors_sql_database, adapter_type: "postgresql")
      expect(db.default_port).to eq(5432)
    end

    it "returns 3306 for mysql" do
      db = build(:connectors_sql_database, adapter_type: "mysql")
      expect(db.default_port).to eq(3306)
    end

    it "returns nil for sqlite" do
      db = build(:connectors_sql_database, adapter_type: "sqlite")
      expect(db.default_port).to be_nil
    end
  end

  describe "#effective_port" do
    it "returns the port when set" do
      db = build(:connectors_sql_database, port: 5433)
      expect(db.effective_port).to eq(5433)
    end

    it "returns the default port when port is nil" do
      db = build(:connectors_sql_database, port: nil, adapter_type: "postgresql")
      expect(db.effective_port).to eq(5432)
    end
  end

  describe "#display_host" do
    it "returns host:port/database when individual fields are used" do
      db = build(:connectors_sql_database, host: "myhost", port: 5432, database_name: "mydb")
      expect(db.display_host).to eq("myhost:5432/mydb")
    end

    it "returns '(connection string)' when connection string is set" do
      db = build(:connectors_sql_database, connection_string: "postgresql://localhost/test")
      expect(db.display_host).to eq("(connection string)")
    end
  end

  describe "clear_dependent_tool_schemas" do
    it "clears dependent tool schemas when host changes" do
      db = create(:connectors_sql_database)
      sql_query = create(:tools_sql_query,
                         connector: db,
                         discovered_schema: { "objects" => [{ "name" => "t", "type" => "table" }] },
                         schema_discovered_at: Time.current,
                         selected_objects: [{ "name" => "t" }],)

      db.update!(host: "new-host.example.com")

      sql_query.reload
      expect(sql_query.schema_discovered_at).to be_nil
      expect(sql_query.discovered_schema).to eq({})
      expect(sql_query.selected_objects).to eq([])
    end

    it "does not clear schemas when non-connection field changes" do
      db = create(:connectors_sql_database)
      sql_query = create(:tools_sql_query,
                         connector: db,
                         discovered_schema: { "objects" => [{ "name" => "t", "type" => "table" }] },
                         schema_discovered_at: Time.current,
                         selected_objects: [{ "name" => "t" }],)

      db.update!(max_results: 200)

      sql_query.reload
      expect(sql_query.schema_discovered_at).to be_present
      expect(sql_query.discovered_schema).to eq({ "objects" => [{ "name" => "t", "type" => "table" }] })
    end

    it "does not fail when no dependent tools exist" do
      db = create(:connectors_sql_database)
      expect { db.update!(host: "new-host.example.com") }.not_to raise_error
    end

    it "skips tools without discovered schemas" do
      db = create(:connectors_sql_database)
      sql_query = create(:tools_sql_query,
                         connector: db,
                         discovered_schema: {},
                         schema_discovered_at: nil,
                         selected_objects: [],)

      db.update!(host: "new-host.example.com")

      sql_query.reload
      expect(sql_query.schema_discovered_at).to be_nil
      expect(sql_query.discovered_schema).to eq({})
    end

    it "skips dependent tools whose configurator is missing" do
      db = build(:connectors_sql_database)
      relation = instance_double(ActiveRecord::Relation)
      orphan_tool = instance_double(Tool, configurator: nil)

      allow(Tool).to receive(:by_type).with(Tools::SqlQuery.type_key).and_return(relation)
      allow(relation).to receive(:where).and_return(relation)
      allow(relation).to receive(:find_each).and_yield(orphan_tool)

      expect do
        db.on_configuration_change(db, { "host" => "old" }, { "host" => "new" })
      end.not_to raise_error
    end

    it "does nothing when no dependent tools are linked" do
      db = create(:connectors_sql_database)
      expect { db.update!(host: "orphaned-host.example.com") }.not_to raise_error
    end
  end

  describe "#connection_string?" do
    it "returns true when connection string is present" do
      db = build(:connectors_sql_database, connection_string: "postgresql://localhost/test")
      expect(db).to be_connection_string
    end

    it "returns false when connection string is blank" do
      db = build(:connectors_sql_database, connection_string: nil)
      expect(db).not_to be_connection_string
    end
  end

  describe "DEFAULT_PORTS" do
    it "has correct ports for all adapter types" do
      expect(described_class::DEFAULT_PORTS["postgresql"]).to eq(5432)
      expect(described_class::DEFAULT_PORTS["mysql"]).to eq(3306)
      expect(described_class::DEFAULT_PORTS["sqlite"]).to be_nil
      expect(described_class::DEFAULT_PORTS["sqlserver"]).to eq(1433)
      expect(described_class::DEFAULT_PORTS["oracle"]).to eq(1521)
    end
  end

  describe ".build_from_params" do
    it "builds an instance from raw ActionController::Parameters" do
      raw = ActionController::Parameters.new(
        sql_database: { adapter_type: "postgresql", host: "db.example.com", port: "5432" },
      )
      db = described_class.build_from_params(raw)
      expect(db).to be_a(described_class)
      expect(db.host).to eq("db.example.com")
    end
  end

  describe "#summary" do
    it "returns a string combining adapter type and display host" do
      db = build(:connectors_sql_database, adapter_type: "postgresql", host: "db.example.com",
                                           port: 5432, database_name: "mydb",)
      expect(db.configurator.summary).to be_a(String)
      expect(db.configurator.summary).to include("Postgresql")
    end

    it "handles nil adapter_type gracefully" do
      db = build(:connectors_sql_database, host: "db.example.com", port: 5432, database_name: "mydb")
      allow(db.configurator).to receive(:adapter_type).and_return(nil)
      summary = db.configurator.summary
      expect(summary).to include("—")
    end

    it "returns connection string display for connection string mode" do
      db = build(:connectors_sql_database, connection_string: "postgresql://localhost/test")
      expect(db.configurator.summary).to include("(connection string)")
    end
  end

  describe "#connection_test_params" do
    it "returns a compact hash of connection parameters" do
      db = build(:connectors_sql_database, adapter_type: "postgresql", host: "localhost",
                                           port: 5432, database_name: "mydb",
                                           username: "user", ssl_enabled: false,)
      params = db.configurator.connection_test_params
      expect(params[:adapter_type]).to eq("postgresql")
      expect(params[:host]).to eq("localhost")
      expect(params[:database_name]).to eq("mydb")
    end

    it "omits nil values" do
      db = build(:connectors_sql_database, connection_string: nil, username: nil)
      params = db.configurator.connection_test_params
      expect(params).not_to have_key(:connection_string)
    end
  end

  describe "#to_configuration" do
    it "removes blank encrypted_password" do
      db = build(:connectors_sql_database, encrypted_password: "")
      config = db.configurator.to_configuration
      expect(config).not_to have_key("encrypted_password")
    end

    it "keeps non-blank encrypted_password" do
      db = build(:connectors_sql_database, encrypted_password: "secret")
      config = db.configurator.to_configuration
      expect(config["encrypted_password"]).to eq("secret")
    end
  end

  describe "#read_only?" do
    it "returns true when read_only is true" do
      db = build(:connectors_sql_database, read_only: true)
      expect(db.read_only?).to be(true)
    end

    it "returns false when read_only is false" do
      db = build(:connectors_sql_database, read_only: false)
      expect(db.read_only?).to be(false)
    end
  end

  describe "#ssl_enabled?" do
    it "returns true when ssl_enabled is true" do
      db = build(:connectors_sql_database, ssl_enabled: true)
      expect(db.ssl_enabled?).to be(true)
    end

    it "returns false when ssl_enabled is false" do
      db = build(:connectors_sql_database, ssl_enabled: false)
      expect(db.ssl_enabled?).to be(false)
    end
  end
end
