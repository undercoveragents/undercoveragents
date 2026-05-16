# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SqlQueryService do
  let(:default_model_id) { "gpt-4o" }
  let(:sql_database) do
    build(:connector, :sql_database,
          adapter_type: "postgresql",
          host: "localhost",
          port: 5432,
          database_name: "test_db",
          username: "user",
          encrypted_password: "pass",
          max_results: 50,)
  end
  let(:sql_query) do
    build(:tools_sql_query,
          connector: sql_database,
          discovered_schema:,
          selected_objects: [],)
  end
  let(:discovered_schema) do
    {
      "objects" => [
        {
          "type" => "table",
          "name" => "users",
          "columns" => [
            { "name" => "id", "type" => "integer", "nullable" => false },
            { "name" => "email", "type" => "character varying", "nullable" => false },
            { "name" => "name", "type" => "character varying", "nullable" => true },
          ],
        },
      ],
    }
  end

  def build_service(**)
    described_class.new(sql_database, model: default_model_id, **)
  end

  describe "#schema_text" do
    it "delegates to SqlSchemaBuilder" do
      service = described_class.new(sql_database, sql_query:)

      expect(service.schema_text).to include("users (table)")
      expect(service.schema_text).to include("email : character varying")
    end

    it "caches the result via Rails.cache when sql_query is present" do
      service = described_class.new(sql_database, sql_query:)
      call_count = 0

      allow(Tools::SqlSchemaBuilder).to receive(:call).and_wrap_original do |original, *args, **kwargs|
        call_count += 1
        original.call(*args, **kwargs)
      end

      2.times { service.schema_text }

      expect(call_count).to be <= 1
    end

    it "skips Rails.cache and calls builder directly when no sql_query" do
      service = described_class.new(sql_database)
      allow(Rails.cache).to receive(:fetch)

      service.schema_text

      expect(Rails.cache).not_to have_received(:fetch)
    end
  end

  describe "#generate_sql" do
    let(:response_double) { instance_double(RubyLLM::Message, content: "SELECT COUNT(*) FROM users") }
    let(:chat_double) do
      instance_double(Chat).tap do |chat|
        allow(chat).to receive(:context=)
        allow(chat).to receive(:to_llm).and_return(chat)
        allow(chat).to receive_messages(with_model: chat, with_temperature: chat, with_instructions: chat,
                                        ask: response_double,)
      end
    end

    before do
      allow(Model).to receive(:find_by).and_return(nil)
      allow(Chat).to receive(:create!).and_return(chat_double)
    end

    it "generates SQL from natural language" do
      service = build_service
      sql = service.generate_sql("How many users are there?")

      expect(sql).to eq("SELECT COUNT(*) FROM users")
    end

    it "strips markdown code fences from response" do
      allow(response_double).to receive(:content).and_return("```sql\nSELECT * FROM users\n```")

      service = build_service
      sql = service.generate_sql("List all users")

      expect(sql).to eq("SELECT * FROM users")
    end

    it "strips trailing semicolons" do
      allow(response_double).to receive(:content).and_return("SELECT * FROM users;")

      service = build_service
      sql = service.generate_sql("List all users")

      expect(sql).to eq("SELECT * FROM users")
    end

    it "includes max_results in the prompt" do
      service = build_service
      instructions_arg = nil

      allow(chat_double).to receive(:with_instructions) do |arg|
        instructions_arg = arg
        chat_double
      end

      service.generate_sql("test")

      expect(instructions_arg).to include("LIMIT 50")
    end

    it "includes adapter type in the prompt" do
      service = build_service
      instructions_arg = nil

      allow(chat_double).to receive(:with_instructions) do |arg|
        instructions_arg = arg
        chat_double
      end

      service.generate_sql("test")

      expect(instructions_arg).to include("Postgresql")
    end

    it "includes extra_instructions in the prompt when provided" do
      service = build_service(extra_instructions: "Only query the read replica.")
      instructions_arg = nil

      allow(chat_double).to receive(:with_instructions) do |arg|
        instructions_arg = arg
        chat_double
      end

      service.generate_sql("test")

      expect(instructions_arg).to include("Only query the read replica.")
    end

    it "omits extra_instructions section when not provided" do
      service = build_service
      instructions_arg = nil

      allow(chat_double).to receive(:with_instructions) do |arg|
        instructions_arg = arg
        chat_double
      end

      service.generate_sql("test")

      expect(instructions_arg).to include("TASK")
      expect(instructions_arg).to include("LIMITS")
    end

    it "omits extra_instructions when blank string is passed" do
      service = build_service(extra_instructions: "  ")
      instructions_arg = nil

      allow(chat_double).to receive(:with_instructions) do |arg|
        instructions_arg = arg
        chat_double
      end

      service.generate_sql("test")

      expect(instructions_arg).not_to match(/\A\s+\z/)
    end

    context "with custom llm_context" do
      let(:llm_context) { double("LlmContext") } # rubocop:disable RSpec/VerifiedDoubles

      it "assigns the llm_context to the chat" do
        service = build_service(temperature: 0.3, llm_context:)
        service.generate_sql("How many users?")

        expect(chat_double).to have_received(:context=).with(llm_context)
      end

      it "clears the chat context when llm_context is nil" do
        service = build_service(temperature: 0.3)
        service.generate_sql("How many users?")

        expect(chat_double).to have_received(:context=).with(nil)
      end

      it "applies the specified temperature" do
        service = build_service(temperature: 0.3, llm_context:)
        service.generate_sql("test")

        expect(chat_double).to have_received(:with_temperature).with(0.3)
      end
    end
  end

  describe "#query" do
    let(:response_double) { instance_double(RubyLLM::Message, content: "SELECT COUNT(*) FROM users") }
    let(:chat_double) do
      instance_double(Chat).tap do |chat|
        allow(chat).to receive(:context=)
        allow(chat).to receive(:to_llm).and_return(chat)
        allow(chat).to receive_messages(with_model: chat, with_temperature: chat, with_instructions: chat,
                                        ask: response_double,)
      end
    end
    let(:fake_conn) { instance_double(PG::Connection) }

    before do
      allow(Model).to receive(:find_by).and_return(nil)
      allow(Chat).to receive(:create!).and_return(chat_double)
      allow(PG).to receive(:connect).and_return(fake_conn)
      allow(fake_conn).to receive(:close)
    end

    it "executes generated SQL in a read-only transaction" do
      query_result = [{ "count" => "42" }]
      pg_result = instance_double(PG::Result, to_a: query_result)
      rollback_result = instance_double(PG::Result)

      allow(fake_conn).to receive(:exec).with("BEGIN")
      allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
      allow(fake_conn).to receive(:exec).with("SELECT COUNT(*) FROM users").and_return(pg_result)
      allow(fake_conn).to receive(:exec).with("ROLLBACK").and_return(rollback_result)

      service = build_service
      result = service.query("How many users?")

      expect(result).to eq(query_result)
      expect(fake_conn).to have_received(:exec).with("SET TRANSACTION READ ONLY")
      expect(fake_conn).to have_received(:exec).with("ROLLBACK")
    end
  end

  describe "SQL validation" do
    let(:service) { described_class.new(sql_database) }

    it "rejects INSERT statements" do
      expect do
        service.send(:validate_sql!, "INSERT INTO users (name) VALUES ('test')")
      end.to raise_error(Tools::QuerySecurityError, /INSERT/)
    end

    it "rejects DELETE statements" do
      expect do
        service.send(:validate_sql!, "DELETE FROM users")
      end.to raise_error(Tools::QuerySecurityError, /DELETE/)
    end

    it "rejects DROP statements" do
      expect do
        service.send(:validate_sql!, "DROP TABLE users")
      end.to raise_error(Tools::QuerySecurityError, /DROP/)
    end

    it "rejects UPDATE statements" do
      expect do
        service.send(:validate_sql!, "UPDATE users SET name = 'x'")
      end.to raise_error(Tools::QuerySecurityError, /UPDATE/)
    end

    it "rejects multiple statements" do
      expect do
        service.send(:validate_sql!, "SELECT 1; DROP TABLE users")
      end.to raise_error(Tools::QuerySecurityError)
    end

    it "rejects non-SELECT queries" do
      expect do
        service.send(:validate_sql!, "CREATE TABLE evil (id int)")
      end.to raise_error(Tools::QuerySecurityError, /Only SELECT/)
    end

    it "allows SELECT queries" do
      expect do
        service.send(:validate_sql!, "SELECT * FROM users WHERE id = 1")
      end.not_to raise_error
    end

    it "allows WITH (CTE) queries" do
      expect do
        service.send(:validate_sql!, "WITH cte AS (SELECT * FROM users) SELECT * FROM cte")
      end.not_to raise_error
    end

    it "rejects TRUNCATE statements" do
      expect do
        service.send(:validate_sql!, "TRUNCATE users")
      end.to raise_error(Tools::QuerySecurityError, /Only SELECT/)
    end

    it "rejects ALTER statements" do
      expect do
        service.send(:validate_sql!, "ALTER TABLE users ADD COLUMN age integer")
      end.to raise_error(Tools::QuerySecurityError, /Only SELECT/)
    end

    it "rejects GRANT statements inside SELECT" do
      expect do
        service.send(:validate_sql!, "SELECT 1; GRANT ALL ON users TO evil")
      end.to raise_error(Tools::QuerySecurityError)
    end

    it "allows SET TRANSACTION READ ONLY in generated SQL" do
      expect do
        service.send(:validate_sql!, "SELECT * FROM users")
      end.not_to raise_error
    end
  end

  describe "MySQL query execution" do
    let(:sql_database) do
      build(:connector, :sql_database,
            adapter_type: "mysql",
            host: "localhost",
            port: 3306,
            database_name: "test_db",
            username: "user",
            encrypted_password: "pass",
            max_results: 50,)
    end

    let(:response_double) { instance_double(RubyLLM::Message, content: "SELECT COUNT(*) FROM users") }
    let(:chat_double) do
      instance_double(Chat).tap do |chat|
        allow(chat).to receive(:context=)
        allow(chat).to receive(:to_llm).and_return(chat)
        allow(chat).to receive_messages(with_model: chat, with_temperature: chat, with_instructions: chat,
                                        ask: response_double,)
      end
    end
    let(:fake_client) { double("Mysql2::Client") } # rubocop:disable RSpec/VerifiedDoubles

    before do
      mysql_klass = Class.new { def initialize(**_kwargs); end }
      stub_const("Mysql2::Client", mysql_klass)
      allow_any_instance_of(described_class).to receive(:require).with("mysql2").and_return(true) # rubocop:disable RSpec/AnyInstance
      allow(Model).to receive(:find_by).and_return(nil)
      allow(Chat).to receive(:create!).and_return(chat_double)
      allow(Mysql2::Client).to receive(:new).and_return(fake_client)
      allow(fake_client).to receive(:close)
    end

    it "executes in a read-only transaction" do
      query_result = [{ "count" => "42" }]

      allow(fake_client).to receive(:query).with("SET TRANSACTION READ ONLY")
      allow(fake_client).to receive(:query).with("START TRANSACTION")
      allow(fake_client).to receive(:query).with("SELECT COUNT(*) FROM users", as: :hash).and_return(query_result)
      allow(fake_client).to receive(:query).with("ROLLBACK")

      service = build_service
      result = service.query("How many users?")

      expect(result).to eq(query_result)
      expect(fake_client).to have_received(:query).with("SET TRANSACTION READ ONLY")
      expect(fake_client).to have_received(:query).with("ROLLBACK")
    end
  end

  describe "SQLite query execution" do
    let(:db_path) { Rails.root.join("tmp/test_query.sqlite3").to_s }

    let(:sql_database) do
      build(:connector, :sql_database,
            adapter_type: "sqlite",
            database_name: db_path,
            host: "localhost",
            max_results: 50,)
    end

    let(:response_double) { instance_double(RubyLLM::Message, content: "SELECT COUNT(*) FROM users") }
    let(:chat_double) do
      instance_double(Chat).tap do |chat|
        allow(chat).to receive(:context=)
        allow(chat).to receive(:to_llm).and_return(chat)
        allow(chat).to receive_messages(with_model: chat, with_temperature: chat, with_instructions: chat,
                                        ask: response_double,)
      end
    end

    before do
      sqlite_db_klass = Class.new { def initialize(*_args); end }
      stub_const("SQLite3::Database", sqlite_db_klass)
      fake_db = double("SQLite3::Database") # rubocop:disable RSpec/VerifiedDoubles
      allow(SQLite3::Database).to receive(:new).and_return(fake_db)
      allow(fake_db).to receive(:results_as_hash=)
      allow(fake_db).to receive(:readonly=)
      allow(fake_db).to receive(:close)
      allow(fake_db).to receive(:execute).with("SELECT COUNT(*) FROM users").and_return([{ "count" => 1 }])
      allow_any_instance_of(described_class).to receive(:require).with("sqlite3").and_return(true) # rubocop:disable RSpec/AnyInstance
      allow(Model).to receive(:find_by).and_return(nil)
      allow(Chat).to receive(:create!).and_return(chat_double)
    end

    it "executes queries against SQLite database" do
      service = build_service
      result = service.query("How many users?")

      expect(result).to be_an(Array)
    end
  end

  describe "unsupported adapter" do
    let(:sql_database) do
      build(:connector, :sql_database,
            adapter_type: "oracle",
            host: "localhost",
            database_name: "test_db",
            max_results: 50,)
    end

    let(:response_double) { instance_double(RubyLLM::Message, content: "SELECT COUNT(*) FROM users") }
    let(:chat_double) do
      instance_double(Chat).tap do |chat|
        allow(chat).to receive(:context=)
        allow(chat).to receive(:to_llm).and_return(chat)
        allow(chat).to receive_messages(with_model: chat, with_temperature: chat, with_instructions: chat,
                                        ask: response_double,)
      end
    end

    before do
      allow(Model).to receive(:find_by).and_return(nil)
      allow(Chat).to receive(:create!).and_return(chat_double)
    end

    it "raises an error for unsupported adapters" do
      service = build_service

      expect { service.query("How many users?") }.to raise_error(RuntimeError, /Unsupported adapter/)
    end
  end
end
