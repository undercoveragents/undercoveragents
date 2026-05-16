# frozen_string_literal: true

# == Schema Information
#
# Table name: tools_sql_queries
# Database name: primary
#
#  id                                  :bigint           not null, primary key
#  discovered_schema                   :jsonb            not null
#  enhanced_description                :text
#  instruction_generation_completed_at :datetime
#  instruction_generation_error        :text
#  instruction_generation_started_at   :datetime
#  instruction_generation_status       :string
#  instructions                        :text
#  llm_config_source                   :string           default("inherit"), not null
#  schema_analysis_completed_at        :datetime
#  schema_analysis_error               :text
#  schema_analysis_started_at          :datetime
#  schema_analysis_status              :string
#  schema_discovered_at                :datetime
#  selected_objects                    :jsonb            not null
#  temperature                         :float
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  connector_id                        :bigint           not null
#  llm_connector_id                    :bigint
#  model_id                            :string
#  schema_analysis_llm_connector_id    :bigint
#  schema_analysis_model_id            :string
#
# Indexes
#
#  index_tools_sql_queries_on_connector_id                      (connector_id)
#  index_tools_sql_queries_on_llm_connector_id                  (llm_connector_id)
#  index_tools_sql_queries_on_schema_analysis_llm_connector_id  (schema_analysis_llm_connector_id)
#
# Foreign Keys
#
#  fk_rails_...  (connector_id => connectors.id)
#  fk_rails_...  (llm_connector_id => connectors.id)
#  fk_rails_...  (schema_analysis_llm_connector_id => connectors.id)
#
require "rails_helper"

RSpec.describe Tools::SqlQuery do
  describe ".register_builtin_tools" do
    around do |example|
      original_definitions = BuiltinTools::Registry.definitions.dup
      BuiltinTools::Registry.definitions.clear
      example.run
    ensure
      BuiltinTools::Registry.definitions.clear
      BuiltinTools::Registry.definitions.merge!(original_definitions)
    end

    let(:registrations) do
      Object.new.tap do |registry|
        registry.define_singleton_method(:tool_call_presentation) do |**|
          {
            running_messages: ["Working…"],
            complete_messages: ["Done."],
          }
        end
      end
    end

    before do
      described_class.register_builtin_tools(registrations)
    end

    it "builds the schema explorer builtin via its registered factory" do
      sql_database = Object.new
      runtime_tool = Object.new

      allow(SchemaExplorerTool).to receive(:for_sql_database).with(sql_database).and_return(runtime_tool)

      expect(BuiltinTools::Registry.build("sql.schema_explorer", sql_database:)).to be(runtime_tool)
    end
  end

  describe "tool designer metadata" do
    it "declares plugin-owned field hints" do
      expect(described_class.tool_designer_field_hints).to eq(
        "connector_id" => { "resource_kind" => "sql_database_connectors" },
        "llm_connector_id" => { "resource_kind" => "llm_connectors" },
        "model_id" => {
          "resource_kind" => "models",
          "note" => "Pass connector_id: llm_connector_id.",
        },
      )
    end

    it "does not expose schema-analysis setup as editable fields" do
      expect(described_class.tool_designer_editable_attributes).not_to include(
        "schema_analysis_llm_connector_id",
        "schema_analysis_model_id",
      )
    end
  end

  describe "persistence" do
    it "#id returns the backing tool's id" do
      sq = create(:tools_sql_query)
      expect(sq.id).to eq(sq._tool_record.id)
    end

    it "#id returns nil when no _tool_record is set" do
      sq = build(:tools_sql_query)
      expect(sq.id).to be_nil
    end

    it "#reload refreshes attributes from the database" do
      sq = create(:tools_sql_query)
      sq._tool_record.update_column(:configuration, sq._tool_record.configuration.merge("model_id" => "test-model")) # rubocop:disable Rails/SkipsModelValidations
      sq.reload
      expect(sq.model_id).to eq("test-model")
    end

    it "#reload returns self when no _tool_record is set" do
      sq = build(:tools_sql_query)
      expect(sq.reload).to be(sq)
    end

    it "== compares by id" do
      sq1 = create(:tools_sql_query)
      sq2 = create(:tools_sql_query)
      expect(sq1).not_to eq(sq2)
      expect(sq1.reload).to eq(sq1)
    end

    it "== returns false for non-SqlQuery objects" do
      sq = create(:tools_sql_query)
      expect(sq == "other").to be(false)
    end

    it "== falls through to object identity for unsaved objects" do
      sq1 = build(:tools_sql_query)
      sq2 = build(:tools_sql_query)
      expect(sq1).not_to eq(sq2)
      myself = sq1
      expect(sq1).to eq(myself)
    end

    it "#tool returns nil when _tool_record is not set" do
      sq = build(:tools_sql_query)
      expect(sq.tool).to be_nil
    end
  end

  describe "connector accessors" do
    it "returns connector by id" do
      sql_connector = create(:connector, :sql_database)
      sq = build(:tools_sql_query, connector: sql_connector)
      expect(sq.connector).to eq(sql_connector)
    end

    it "returns nil when llm_connector_id is blank" do
      sq = build(:tools_sql_query, llm_config_source: "inherit")
      expect(sq.llm_connector).to be_nil
    end

    it "clears connector_id when connector= nil" do
      sq = build(:tools_sql_query)
      sq.connector = nil
      expect(sq.connector_id).to be_nil
    end

    it "clears llm_connector_id when llm_connector= nil" do
      sq = build(:tools_sql_query)
      sq.llm_connector = nil
      expect(sq.llm_connector_id).to be_nil
    end

    it "returns nil when schema_analysis_llm_connector_id is blank" do
      sq = build(:tools_sql_query, schema_analysis_llm_connector_id: nil)
      expect(sq.schema_analysis_llm_connector).to be_nil
    end

    it "clears schema_analysis_llm_connector_id when schema_analysis_llm_connector= nil" do
      sq = build(:tools_sql_query)
      sq.schema_analysis_llm_connector = nil
      expect(sq.schema_analysis_llm_connector_id).to be_nil
    end

    it "loads llm_connector from DB when cache is cold" do
      sq = described_class.new(llm_connector_id: nil)
      expect(sq.llm_connector).to be_nil
    end

    it "loads llm_connector by id when the cache is cold" do
      llm_connector = create(:connector, :llm_provider)
      sq = described_class.new(llm_connector_id: llm_connector.id)

      expect(sq.llm_connector).to eq(llm_connector)
    end

    it "re-fetches llm_connector when the cached instance is explicitly nil" do
      llm_connector = create(:connector, :llm_provider)
      sq = described_class.new(llm_connector_id: llm_connector.id)

      sq.llm_connector = nil
      sq.llm_connector_id = llm_connector.id

      expect(sq.llm_connector).to eq(llm_connector)
    end

    it "returns cached connector on repeated access" do
      sql_connector = create(:connector, :sql_database)
      sq = build(:tools_sql_query, connector: sql_connector)
      first = sq.connector
      second = sq.connector
      expect(second).to be(first)
    end

    it "re-fetches connector when connector_id changes" do
      sql_connector1 = create(:connector, :sql_database)
      sql_connector2 = create(:connector, :sql_database)
      sq = build(:tools_sql_query, connector: sql_connector1)
      sq.connector # warm cache
      sq.connector_id = sql_connector2.id
      expect(sq.connector).to eq(sql_connector2)
    end

    it "sets connector_id when connector= is used with a record" do
      sql_connector = create(:connector, :sql_database)
      sq = build(:tools_sql_query)
      sq.connector = sql_connector
      expect(sq.connector_id).to eq(sql_connector.id)
    end

    it "sets llm_connector_id when llm_connector= is used with a record" do
      llm_connector = create(:connector, :llm_provider)
      sq = build(:tools_sql_query)
      sq.llm_connector = llm_connector
      expect(sq.llm_connector_id).to eq(llm_connector.id)
    end

    it "sets schema_analysis_llm_connector_id when schema_analysis_llm_connector= is used" do
      llm_connector = create(:connector, :llm_provider)
      sq = build(:tools_sql_query)
      sq.schema_analysis_llm_connector = llm_connector
      expect(sq.schema_analysis_llm_connector_id).to eq(llm_connector.id)
    end

    it "re-fetches schema_analysis_llm_connector when the cached id changes" do
      first_connector = create(:connector, :llm_provider)
      second_connector = create(:connector, :llm_provider)
      sq = build(:tools_sql_query, schema_analysis_llm_connector: first_connector)

      sq.schema_analysis_llm_connector
      sq.schema_analysis_llm_connector_id = second_connector.id

      expect(sq.schema_analysis_llm_connector).to eq(second_connector)
    end

    it "re-fetches schema_analysis_llm_connector when the cached instance is explicitly nil" do
      llm_connector = create(:connector, :llm_provider)
      sq = described_class.new(schema_analysis_llm_connector_id: llm_connector.id)

      sq.schema_analysis_llm_connector = nil
      sq.schema_analysis_llm_connector_id = llm_connector.id

      expect(sq.schema_analysis_llm_connector).to eq(llm_connector)
    end
  end

  describe "persistence guard rails" do
    it "raises when save! is called without a backing tool record" do
      expect { build(:tools_sql_query).save! }.to raise_error("No _tool_record set")
    end
  end

  describe "validations" do
    it { is_expected.to validate_length_of(:instructions).is_at_most(10_000) }

    it { is_expected.to validate_inclusion_of(:llm_config_source).in_array(["inherit", "custom"]) }

    it "validates connector is an SQL database" do
      other_connector = create(:connector, :llm_provider)
      sql_query = build(:tools_sql_query, connector: other_connector)
      expect(sql_query).not_to be_valid
      expect(sql_query.errors[:connector]).to include("must be an SQL Database connector")
    end

    it "allows SQL database connectors" do
      sql_connector = create(:connector, :sql_database)
      sql_query = build(:tools_sql_query, connector: sql_connector)
      expect(sql_query).to be_valid
    end

    context "when llm_config_source is custom" do
      it "requires model_id" do
        sq = build(:tools_sql_query, llm_config_source: "custom", model_id: nil,
                                     llm_connector: create(:connector, :llm_provider),
                                     temperature: 0.5,)
        expect(sq).not_to be_valid
        expect(sq.errors[:model_id]).to include("can't be blank")
      end

      it "requires temperature" do
        sq = build(:tools_sql_query, llm_config_source: "custom", temperature: nil,
                                     llm_connector: create(:connector, :llm_provider),
                                     model_id: "gpt-4.1-mini",)
        expect(sq).not_to be_valid
        expect(sq.errors[:temperature]).to include("can't be blank")
      end

      it "validates temperature range" do
        sq = build(:tools_sql_query, llm_config_source: "custom", temperature: 3.0,
                                     llm_connector: create(:connector, :llm_provider),
                                     model_id: "gpt-4.1-mini",)
        expect(sq).not_to be_valid
        expect(sq.errors[:temperature]).to be_present
      end

      it "validates llm_connector is an LLM Provider" do
        sql_connector = create(:connector, :sql_database)
        sq = build(:tools_sql_query, llm_config_source: "custom",
                                     llm_connector: sql_connector,
                                     model_id: "gpt-4.1-mini", temperature: 0.5,)
        expect(sq).not_to be_valid
        expect(sq.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
      end

      it "skips llm_connector validation when llm_connector_id is blank" do
        sq = build(:tools_sql_query, llm_config_source: "custom",
                                     llm_connector: nil,
                                     model_id: "gpt-4.1-mini", temperature: 0.5,)
        expect(sq.errors[:llm_connector_id]).to be_empty
      end

      it "is valid with all custom fields set" do
        sq = build(:tools_sql_query, :with_custom_llm)
        expect(sq).to be_valid
      end
    end

    context "when llm_config_source is inherit" do
      it "does not require model_id or temperature" do
        sq = build(:tools_sql_query, llm_config_source: "inherit", model_id: nil, temperature: nil)
        expect(sq).to be_valid
      end
    end

    it "rejects connectors outside the tool tenant" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      foreign_connector = create(:connector, :sql_database, tenant: create(:tenant))
      sq = create(:tool, :sql_query, operation:).configurator
      sq.connector_id = foreign_connector.id

      expect(sq).not_to be_valid
      expect(sq.errors[:connector]).to include("must be an SQL Database connector")
    end

    it "returns nil when the cached connector has been cleared" do
      sq = build(:tools_sql_query)
      sq.connector = nil

      expect(sq.connector).to be_nil
    end
  end

  describe "#selected_object_names" do
    it "extracts names from selected objects" do
      sq = build(:tools_sql_query, selected_objects: [{ "name" => "users" }, { "name" => "orders" }])
      expect(sq.selected_object_names).to eq(["users", "orders"])
    end

    it "returns empty array when no objects selected" do
      sq = build(:tools_sql_query, selected_objects: [])
      expect(sq.selected_object_names).to eq([])
    end

    it "handles symbol keys" do
      sq = build(:tools_sql_query, selected_objects: [{ name: "users" }, { name: "orders" }])
      expect(sq.selected_object_names).to eq(["users", "orders"])
    end

    it "returns empty array when selected_objects is not an array" do
      sq = build(:tools_sql_query, selected_objects: nil)
      expect(sq.selected_object_names).to eq([])
    end
  end

  describe "shared widget configuration" do
    it "defaults to the shared widget behavior" do
      sql_query = build(:tools_sql_query)

      expect(sql_query.tool_widget_customized?).to be(false)
      expect(sql_query.tool_widget_running_mode).to eq("random")
      expect(sql_query.tool_widget_running_interval_ms).to eq(2200)
    end

    it "does not persist default widget settings into configuration" do
      sql_query = build(:tools_sql_query)

      expect(sql_query.to_configuration.keys.grep(/tool_widget_/)).to be_empty
    end

    it "persists a configured compaction policy and strips blank ones" do
      sql_query = build(:tools_sql_query, tool_compaction_policy: "drop_all")
      expect(sql_query.to_configuration["tool_compaction_policy"]).to eq("drop_all")

      blank = build(:tools_sql_query, tool_compaction_policy: "")
      expect(blank.to_configuration).not_to have_key("tool_compaction_policy")
    end

    it "rejects unknown compaction policies via inclusion validation" do
      sql_query = build(:tools_sql_query, tool_compaction_policy: "bogus")
      expect(sql_query).not_to be_valid
      expect(sql_query.errors[:tool_compaction_policy]).to be_present
    end

    it "normalizes compaction policy params, rejecting invalid values" do
      raw = ActionController::Parameters.new(
        sql_query: { tool_widget_running_mode: "rotate", tool_compaction_policy: "bogus" },
      )
      expect(described_class.permitted_params(raw)[:tool_compaction_policy]).to eq("")
    end

    it "accepts a valid compaction policy when submitted" do
      raw = ActionController::Parameters.new(
        sql_query: { tool_widget_running_mode: "rotate", tool_compaction_policy: "drop_all" },
      )
      expect(described_class.permitted_params(raw)[:tool_compaction_policy]).to eq("drop_all")
    end

    it "coerces a blank compaction policy to the empty default" do
      raw = ActionController::Parameters.new(
        sql_query: { tool_widget_running_mode: "rotate", tool_compaction_policy: nil },
      )
      expect(described_class.permitted_params(raw)[:tool_compaction_policy]).to eq("")
    end

    it "validates a custom Font Awesome icon" do
      sql_query = build(:tools_sql_query, tool_widget_icon: "not-a-valid-icon")

      expect(sql_query).not_to be_valid
      expect(sql_query.errors[:tool_widget_icon]).to include("must be a valid Font Awesome class pair")
    end

    it "drops legacy grouped widget params when submitted" do
      raw = ActionController::Parameters.new(
        sql_query: {
          tool_widget_group_enabled: "1",
          tool_widget_group_title: "  Working   on   the   schema task  ",
          tool_widget_running_mode: "rotate",
        },
      )

      permitted = described_class.permitted_params(raw)

      expect(permitted).not_to have_key(:tool_widget_group_enabled)
      expect(permitted).not_to have_key(:tool_widget_group_title)
      expect(permitted[:tool_widget_running_mode]).to eq("rotate")
    end

    it "validates the maximum number of running messages" do
      sql_query = build(
        :tools_sql_query,
        tool_widget_running_messages: Array.new(
          ToolCalls::Presentation::MAX_MESSAGE_COUNT + 1,
        ) { |index| "Step #{index}" },
      )

      expect(sql_query).not_to be_valid
      expect(sql_query.errors[:tool_widget_running_messages]).to include(
        "must contain at most #{ToolCalls::Presentation::MAX_MESSAGE_COUNT} messages",
      )
    end

    it "validates the maximum message length" do
      sql_query = build(
        :tools_sql_query,
        tool_widget_complete_messages: ["x" * (ToolCalls::Presentation::MAX_MESSAGE_LENGTH + 1)],
      )

      expect(sql_query).not_to be_valid
      expect(sql_query.errors[:tool_widget_complete_messages]).to include("messages must be 120 characters or fewer")
    end
  end

  describe "#all_discovered_object_names" do
    it "returns all discovered object names" do
      sq = build(:tools_sql_query, discovered_schema: {
                   "objects" => [
                     { "name" => "users", "type" => "table" },
                     { "name" => "reports", "type" => "view" },
                   ],
                 },)
      expect(sq.all_discovered_object_names).to eq(["users", "reports"])
    end

    it "returns empty array when schema is not a hash" do
      sq = build(:tools_sql_query, discovered_schema: [])
      expect(sq.all_discovered_object_names).to eq([])
    end
  end

  describe "#all_objects_selected?" do
    it "returns true when all discovered objects are selected" do
      sq = build(:tools_sql_query,
                 discovered_schema: { "objects" => [
                   { "name" => "users", "type" => "table" },
                   { "name" => "orders", "type" => "table" },
                 ] },
                 selected_objects: [{ "name" => "users" }, { "name" => "orders" }],)
      expect(sq).to be_all_objects_selected
    end

    it "returns true when no objects are discovered" do
      sq = build(:tools_sql_query, discovered_schema: {}, selected_objects: [])
      expect(sq).to be_all_objects_selected
    end

    it "returns false when only some objects are selected" do
      sq = build(:tools_sql_query,
                 discovered_schema: { "objects" => [
                   { "name" => "users", "type" => "table" },
                   { "name" => "orders", "type" => "table" },
                 ] },
                 selected_objects: [{ "name" => "users" }],)
      expect(sq).not_to be_all_objects_selected
    end
  end

  describe "#sync_selected_after_discovery" do
    let(:sq) do
      build(:tools_sql_query, discovered_schema: {
              "objects" => [
                { "name" => "users", "type" => "table" },
                { "name" => "orders", "type" => "table" },
                { "name" => "products", "type" => "table" },
              ],
            },)
    end

    it "selects everything on first discovery" do
      sq.sync_selected_after_discovery([])
      expect(sq.selected_object_names).to eq(["users", "orders", "products"])
    end

    it "keeps existing selection and adds new objects" do
      sq.sync_selected_after_discovery(["users"])
      expect(sq.selected_object_names).to contain_exactly("users", "orders", "products")
    end

    it "removes objects that no longer exist" do
      sq.sync_selected_after_discovery(["users", "deleted_table"])
      expect(sq.selected_object_names).to contain_exactly("users", "orders", "products")
    end
  end

  describe "#schema_discovered?" do
    it "returns true when schema has been discovered" do
      sq = build(:tools_sql_query,
                 discovered_schema: { "objects" => [] },
                 schema_discovered_at: Time.current,)
      expect(sq).to be_schema_discovered
    end

    it "returns false when schema has NOT been discovered" do
      sq = build(:tools_sql_query, discovered_schema: {}, schema_discovered_at: nil)
      expect(sq).not_to be_schema_discovered
    end
  end

  describe "#tables" do
    it "returns objects of type 'table'" do
      sq = build(:tools_sql_query, discovered_schema: {
                   "objects" => [
                     { "name" => "users", "type" => "table" },
                     { "name" => "user_view", "type" => "view" },
                   ],
                 },)
      expect(sq.tables).to eq([{ "name" => "users", "type" => "table" }])
    end

    it "returns empty array for invalid schema" do
      sq = build(:tools_sql_query, discovered_schema: [])
      expect(sq.tables).to eq([])
    end
  end

  describe "#views" do
    it "returns objects of type 'view'" do
      sq = build(:tools_sql_query, discovered_schema: {
                   "objects" => [
                     { "name" => "users", "type" => "table" },
                     { "name" => "user_view", "type" => "view" },
                   ],
                 },)
      expect(sq.views).to eq([{ "name" => "user_view", "type" => "view" }])
    end
  end

  describe "#materialized_views" do
    it "returns objects of type 'materialized_view'" do
      sq = build(:tools_sql_query, discovered_schema: {
                   "objects" => [
                     { "name" => "daily_stats", "type" => "materialized_view" },
                     { "name" => "users", "type" => "table" },
                   ],
                 },)
      expect(sq.materialized_views).to eq([{ "name" => "daily_stats", "type" => "materialized_view" }])
    end
  end

  describe "#sql_database" do
    it "returns the connector" do
      connector = create(:connector, :sql_database)
      sq = build(:tools_sql_query, connector:)
      expect(sq.sql_database).to eq(connector)
    end

    it "returns nil when connector is nil" do
      sq = build(:tools_sql_query)
      allow(sq).to receive(:connector).and_return(nil)
      expect(sq.sql_database).to be_nil
    end
  end

  describe "#effective_instructions" do
    it "returns instructions when present" do
      sq = build(:tools_sql_query, instructions: "Custom prompt")
      expect(sq.effective_instructions).to eq("Custom prompt")
    end

    it "returns default tool prompt when instructions are blank" do
      sq = build(:tools_sql_query, instructions: nil)
      expect(sq.effective_instructions).to eq(SqlQueryTool::DEFAULT_TOOL_PROMPT)
    end
  end

  describe "#use_custom_llm_config?" do
    it "returns true when llm_config_source is custom" do
      sq = build(:tools_sql_query, llm_config_source: "custom")
      expect(sq.use_custom_llm_config?).to be(true)
    end

    it "returns false when llm_config_source is inherit" do
      sq = build(:tools_sql_query, llm_config_source: "inherit")
      expect(sq.use_custom_llm_config?).to be(false)
    end
  end

  describe "schema analysis associations" do
    it "returns schema_analysis_llm_connector by id" do
      llm_connector = create(:connector, :llm_provider)
      sq = build(:tools_sql_query, schema_analysis_llm_connector: llm_connector)
      expect(sq.schema_analysis_llm_connector).to eq(llm_connector)
    end
  end

  describe "#llm_connector_must_be_llm_provider with nil llm_connector" do
    it "does not add an error when llm_connector_id is set but connector was deleted (nil safe-nav)" do
      sq = build(:tools_sql_query, llm_config_source: "custom",
                                   llm_connector_id: 999_999_999,
                                   model_id: "gpt-4.1",
                                   temperature: 0.7,)
      allow(sq).to receive(:llm_connector).and_return(nil)
      sq.valid?
      # nil llm_connector → &. returns nil → nil != "Connectors::LlmProvider" → adds error
      expect(sq.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end
  end
end
