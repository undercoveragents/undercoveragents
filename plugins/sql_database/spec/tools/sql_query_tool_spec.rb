# frozen_string_literal: true

require "rails_helper"

RSpec.describe SqlQueryTool do
  let(:sql_database) do
    create(:connectors_sql_database,
           name: "HR Database",
           enabled: true,
           adapter_type: "postgresql",
           host: "localhost",
           database_name: "test_db",
           max_results: 100,)
  end

  let(:connector) { sql_database }

  let(:discovered_schema) do
    {
      "objects" => [
        {
          "type" => "table",
          "name" => "employees",
          "columns" => [
            { "name" => "id", "type" => "integer", "nullable" => false },
            { "name" => "name", "type" => "character varying", "nullable" => false },
          ],
        },
      ],
    }
  end

  let(:sql_query) do
    create(:tools_sql_query,
           connector:,
           discovered_schema:,
           selected_objects: [{ "name" => "employees" }],
           schema_discovered_at: Time.current,)
  end

  let(:tool_record) do
    create(:tool, :enabled, name: "HR Database Query", toolable: sql_query)
  end

  describe ".for_tool" do
    it "creates a tool instance for a SQL Query tool" do
      tool = described_class.for_tool(tool_record)

      expect(tool).to be_a(described_class)
    end

    it "raises for non-SQL Query tools" do
      non_sql_tool = build(:tool, toolable: nil)
      allow(non_sql_tool).to receive(:toolable).and_return(instance_double(Connectors::LlmProvider))

      expect do
        described_class.for_tool(non_sql_tool)
      end.to raise_error(ArgumentError, /SQL Query tool/)
    end
  end

  describe "#name" do
    it "derives a unique tool name from the tool record name" do
      tool = described_class.for_tool(tool_record)

      expect(tool.name).to eq("sql_query_hr_database_query")
    end

    it "sanitizes special characters in tool names" do
      tool_record.update!(name: "My DB (Production) #1")
      tool = described_class.for_tool(tool_record)

      expect(tool.name).to match(/\Asql_query_[a-z0-9_]+\z/)
    end
  end

  describe "#description" do
    it "returns generated instructions when schema has been discovered" do
      tool = described_class.for_tool(tool_record)

      expect(tool.description).to include("employees")
      expect(tool.description).to include("read-only")
    end

    it "returns custom instructions when set" do
      sql_query.update!(instructions: "Custom SQL prompt")
      tool = described_class.for_tool(tool_record)

      expect(tool.description).to eq("Custom SQL prompt")
    end
  end

  describe "#execute" do
    let(:tool) { described_class.for_tool(tool_record) }
    let(:service_double) { instance_double(Tools::SqlQueryService) }

    before do
      allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
    end

    it "queries the database and returns formatted results" do
      allow(service_double).to receive(:query).with("How many employees?").and_return([{ "count" => 42 }])

      result = tool.execute(question: "How many employees?")

      expect(result).to include("count")
      expect(result).to include("42")
    end

    it "uses the connector's max_results by default" do
      allow(service_double).to receive(:query).and_return([])

      tool.execute(question: "List employees")

      expect(Tools::SqlQueryService).to have_received(:new) do |db, **_kwargs|
        expect(db.max_results).to eq(100)
      end
    end

    it "overrides max_results when limit is provided" do
      captured_max = nil
      allow(Tools::SqlQueryService).to receive(:new) do |db, **_kwargs|
        captured_max = db.max_results
        service_double
      end
      allow(service_double).to receive(:query).and_return([])

      tool.execute(question: "List employees", limit: 10)

      expect(captured_max).to eq(10)
    end

    it "returns error message on failure" do
      allow(service_double).to receive(:query).and_raise(StandardError.new("connection failed"))
      allow(Rails.logger).to receive(:error)

      result = tool.execute(question: "How many?")

      expect(result).to include("couldn't execute")
      expect(result).to include("connection failed")
    end

    it "returns no-results message for empty results" do
      allow(service_double).to receive(:query).and_return([])

      result = tool.execute(question: "Find nonexistent users")

      expect(result).to eq("No results found.")
    end

    it "returns no-results message for nil results" do
      allow(service_double).to receive(:query).and_return(nil)

      result = tool.execute(question: "Find nothing")

      expect(result).to eq("No results found.")
    end

    it "inspects non-array results (e.g. a string summary)" do
      allow(service_double).to receive(:query).and_return("42 rows affected")

      result = tool.execute(question: "Update something")

      expect(result).to eq('"42 rows affected"')
    end

    it "restores original max_results after execution" do
      allow(service_double).to receive(:query).and_return([])

      tool.execute(question: "test", limit: 5)

      expect(sql_database.max_results).to eq(100)
    end

    it "skips restoring max_results when original_max was nil" do
      # original_max = @sql_database.max_results; if original_max → falsy when nil → assignment skipped
      # Stub max_results to return nil initially, and track the setter
      allow(sql_database).to receive(:max_results).and_return(nil, 10) # nil initially, 10 after limit set
      allow(sql_database).to receive(:max_results=)

      allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:query).and_return([])

      tool.execute(question: "test", limit: 10)

      # With original_max=nil, the ensure block should NOT call max_results= (to restore)
      expect(sql_database).not_to have_received(:max_results=).with(nil)
    end

    context "with custom LLM configuration" do
      let(:llm_connector) do
        create(:connector, :llm_provider, :enabled, name: "Custom LLM")
      end

      let(:sql_query_custom) do
        create(:tools_sql_query,
               connector:,
               discovered_schema:,
               selected_objects: [{ "name" => "employees" }],
               schema_discovered_at: Time.current,
               llm_config_source: "custom",
               llm_connector:,
               model_id: "gpt-4o",
               temperature: 0.3,)
      end

      let(:tool_record_custom) do
        create(:tool, :enabled, name: "Custom LLM Query", toolable: sql_query_custom)
      end

      it "passes custom LLM config to the service" do
        context_double = double("LlmContext") # rubocop:disable RSpec/VerifiedDoubles
        allow(llm_connector).to receive(:build_context).and_return(context_double)

        allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:query).and_return([{ "count" => 1 }])

        described_class.for_tool(tool_record_custom).execute(question: "test")

        expect(Tools::SqlQueryService).to have_received(:new).with(
          anything, hash_including(model: "gpt-4o", temperature: 0.3, llm_context: context_double),
        )
      end

      it "handles nil llm_connector gracefully" do
        sql_query_custom.llm_connector_id = nil

        allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:query).and_return([])

        result = described_class.for_tool(tool_record_custom).execute(question: "test")

        expect(result).to eq("No results found.")
        expect(Tools::SqlQueryService).to have_received(:new).with(
          anything, hash_including(llm_context: nil),
        )
      end
    end

    context "with agent context (inherit)" do
      let(:agent_llm_connector) do
        create(:connector, :llm_provider, :enabled, name: "Agent LLM")
      end

      let(:agent) do
        create(:agent, model_id: "gpt-4o", temperature: 0.5, llm_connector: agent_llm_connector)
      end

      it "passes agent LLM config to the service" do
        context_double = double("LlmContext") # rubocop:disable RSpec/VerifiedDoubles
        allow(agent).to receive(:resolve_llm_context).and_return(context_double)
        allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:query).and_return([{ "count" => 1 }])

        described_class.for_tool(tool_record, agent:).execute(question: "test")

        expect(Tools::SqlQueryService).to have_received(:new).with(
          anything, hash_including(model: "gpt-4o", temperature: 0.5, llm_context: context_double),
        )
      end
    end

    context "with parent chat runtime context" do
      it "inherits model and llm context from the parent chat when no agent is present" do
        parent_model = Struct.new(:model_id).new("gpt-4.1")
        llm_context = Object.new
        parent_chat = Struct.new(:model, :agent, :context).new(parent_model, nil, llm_context)

        allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:query).and_return([{ "count" => 1 }])

        described_class.for_tool(tool_record, parent_chat:).execute(question: "test")

        expect(Tools::SqlQueryService).to have_received(:new).with(
          anything, hash_including(model: "gpt-4.1", llm_context:),
        )
      end

      it "falls back to the parent chat agent runtime config when direct parent chat values are missing" do
        fallback_context = Object.new
        parent_agent = instance_double(Agent,
                                       resolved_model_id: "gpt-4.1-mini",
                                       resolve_llm_context: fallback_context,)
        parent_chat = Struct.new(:model, :agent, :context).new(nil, parent_agent, nil)

        allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:query).and_return([{ "count" => 1 }])

        described_class.for_tool(tool_record, parent_chat:).execute(question: "test")

        expect(Tools::SqlQueryService).to have_received(:new).with(
          anything, hash_including(model: "gpt-4.1-mini", llm_context: fallback_context),
        )
      end

      it "omits inherited runtime config when the parent chat has no direct or agent fallbacks" do
        parent_chat = Struct.new(:model, :agent, :context).new(nil, nil, nil)
        captured_kwargs = nil

        allow(Tools::SqlQueryService).to receive(:new) do |_database, **kwargs|
          captured_kwargs = kwargs
          service_double
        end
        allow(service_double).to receive(:query).and_return([{ "count" => 1 }])

        described_class.for_tool(tool_record, parent_chat:).execute(question: "test")

        expect(captured_kwargs).not_to have_key(:model)
        expect(captured_kwargs).not_to have_key(:llm_context)
      end
    end

    context "with no LLM config (inherit, no agent)" do
      it "passes empty config to the service when there is no parent chat fallback" do
        allow(Tools::SqlQueryService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:query).and_return([{ "count" => 1 }])

        described_class.for_tool(tool_record).execute(question: "test")

        expect(Tools::SqlQueryService).to have_received(:new).with(anything, hash_including({}))
      end
    end
  end

  describe "#parameters" do
    let(:tool) { described_class.for_tool(tool_record) }

    it "has a required question parameter" do
      expect(tool.parameters[:question]).to be_present
      expect(tool.parameters[:question].required).to be(true)
    end

    it "has an optional limit parameter" do
      expect(tool.parameters[:limit]).to be_present
      expect(tool.parameters[:limit].required).to be(false)
    end
  end
end
