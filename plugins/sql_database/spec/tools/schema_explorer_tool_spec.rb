# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchemaExplorerTool do
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

  let(:tool) { described_class.for_sql_database(sql_database) }

  describe ".for_sql_database" do
    it "creates a tool instance" do
      expect(tool).to be_a(described_class)
    end
  end

  describe "#name" do
    it "returns explore_database" do
      expect(tool.name).to eq("explore_database")
    end
  end

  describe "#description" do
    it "returns a non-empty string" do
      expect(tool.description).to be_a(String).and(be_present)
    end
  end

  describe "#execute" do
    context "with valid SELECT query" do
      let(:fake_conn) { instance_double(PG::Connection) }
      let(:result_rows) { [{ "count" => "42" }] }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("SELECT COUNT(*) FROM users").and_return(result_rows)
        allow(fake_conn).to receive(:exec).with("ROLLBACK")
      end

      it "executes the query and returns results" do
        result = tool.execute(sql: "SELECT COUNT(*) FROM users")
        expect(result).to include("42")
      end
    end

    context "with forbidden SQL" do
      it "rejects INSERT statements" do
        result = tool.execute(sql: "INSERT INTO users (name) VALUES ('test')")
        expect(result).to include("Security error")
      end

      it "rejects DROP statements" do
        result = tool.execute(sql: "DROP TABLE users")
        expect(result).to include("Security error")
      end

      it "rejects DELETE statements" do
        result = tool.execute(sql: "DELETE FROM users")
        expect(result).to include("Security error")
      end
    end

    context "with connection error" do
      before do
        allow(PG).to receive(:connect).and_raise(PG::ConnectionBad.new("refused"))
      end

      it "returns a formatted error" do
        result = tool.execute(sql: "SELECT 1")
        expect(result).to include("Query failed")
      end
    end

    context "with empty result set" do
      let(:fake_conn) { instance_double(PG::Connection) }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("SELECT * FROM empty_table").and_return([])
        allow(fake_conn).to receive(:exec).with("ROLLBACK")
      end

      it "returns 'No results.' message" do
        result = tool.execute(sql: "SELECT * FROM empty_table")
        expect(result).to eq("No results.")
      end
    end

    context "with nil result" do
      let(:fake_conn) { instance_double(PG::Connection) }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("SELECT 1").and_return(nil)
        allow(fake_conn).to receive(:exec).with("ROLLBACK")
      end

      it "returns 'No results.' message" do
        result = tool.execute(sql: "SELECT 1")
        expect(result).to eq("No results.")
      end
    end

    context "with UPDATE statement" do
      it "rejects UPDATE" do
        result = tool.execute(sql: "UPDATE users SET name = 'test'")
        expect(result).to include("Security error")
      end
    end

    context "with WITH (CTE) query" do
      let(:fake_conn) { instance_double(PG::Connection) }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("WITH cte AS (SELECT 1) SELECT * FROM cte").and_return([{ "1" => "1" }])
        allow(fake_conn).to receive(:exec).with("ROLLBACK")
      end

      it "allows WITH/CTE queries" do
        result = tool.execute(sql: "WITH cte AS (SELECT 1) SELECT * FROM cte")
        expect(result).not_to include("Security error")
      end
    end

    context "with result exceeding MAX_RESULT_LENGTH" do
      let(:fake_conn) { instance_double(PG::Connection) }
      let(:long_value) { "x" * 9000 }
      let(:result_rows) { [{ "data" => long_value }] }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("SELECT data FROM big_table").and_return(result_rows)
        allow(fake_conn).to receive(:exec).with("ROLLBACK")
      end

      it "truncates the output" do
        result = tool.execute(sql: "SELECT data FROM big_table")
        expect(result).to include("(truncated)")
        expect(result.length).to be <= (described_class::MAX_RESULT_LENGTH + 20)
      end
    end

    context "with result exceeding MAX_RESULT_ROWS" do
      let(:fake_conn) { instance_double(PG::Connection) }
      let(:result_rows) { (1..60).map { |i| { "id" => i.to_s } } }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("SELECT id FROM many_rows").and_return(result_rows)
        allow(fake_conn).to receive(:exec).with("ROLLBACK")
      end

      it "shows row count message" do
        result = tool.execute(sql: "SELECT id FROM many_rows")
        expect(result).to include("Showing #{described_class::MAX_RESULT_ROWS} of 60 rows")
      end
    end

    context "with a forbidden pattern (multi-statement)" do
      it "rejects queries with semicolons" do
        result = tool.execute(sql: "SELECT 1; DROP TABLE users")
        expect(result).to include("Security error")
      end
    end

    context "when result is a non-array object (unusual driver response)" do
      it "wraps a non-array result in an array and formats it" do
        # Calls format_result directly to cover the `result.is_a?(Array) ? result : [result]`
        # false branch AND the `result.respond_to?(:empty?)` false branch.
        result = tool.send(:format_result, 42)
        expect(result).to include("42")
      end
    end

    context "when ROLLBACK fails after a SQL error" do
      let(:fake_conn) { instance_double(PG::Connection) }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("SELECT bad").and_raise(PG::Error.new("query failed"))
        allow(fake_conn).to receive(:exec).with("ROLLBACK").and_raise(PG::ConnectionBad.new("connection down"))
      end

      it "silences the ROLLBACK failure and reports the original query error" do
        result = tool.execute(sql: "SELECT bad")
        expect(result).to include("Query failed")
      end
    end

    context "when SQL fails but ROLLBACK succeeds" do
      let(:fake_conn) { instance_double(PG::Connection) }

      before do
        allow(PG).to receive(:connect).and_return(fake_conn)
        allow(fake_conn).to receive(:close)
        allow(fake_conn).to receive(:exec).with("BEGIN")
        allow(fake_conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
        allow(fake_conn).to receive(:exec).with("SELECT broken").and_raise(PG::Error.new("syntax error"))
        allow(fake_conn).to receive(:exec).with("ROLLBACK")
      end

      it "reports the SQL error to the caller" do
        result = tool.execute(sql: "SELECT broken")
        expect(result).to include("Query failed")
      end
    end

    context "with an unsupported adapter type" do
      let(:oracle_db) do
        create(:connectors_sql_database,
               adapter_type: "oracle",
               host: "localhost",
               port: 1521,
               database_name: "orcl",
               schema_name: "public",
               username: "user",
               encrypted_password: "pass",)
      end
      let(:oracle_tool) { described_class.for_sql_database(oracle_db) }

      it "returns a query failed message for unsupported adapters" do
        result = oracle_tool.execute(sql: "SELECT 1 FROM dual")
        expect(result).to include("Query failed")
      end
    end
  end
end
