# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tools" do
  describe "GET /tools (standalone)" do
    it "returns a successful response" do
      get admin_tools_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "nested routes" do
    def expected_widget_configuration(icon:, interval_ms:, running_messages:, complete_messages:)
      {
        "tool_widget_icon" => icon,
        "tool_widget_running_mode" => "rotate",
        "tool_widget_running_interval_ms" => interval_ms,
        "tool_widget_running_messages" => running_messages,
        "tool_widget_complete_messages" => complete_messages,
      }
    end

    def sql_query_widget_params(widget:, connector_id: nil, tool_name: nil)
      params = {
        tool_type: "sql_query",
        sql_query: {
          tool_widget_icon: widget.fetch(:icon),
          tool_widget_running_mode: "rotate",
          tool_widget_running_interval_ms: widget.fetch(:interval_ms).to_s,
          tool_widget_running_messages_text: widget.fetch(:running_text),
          tool_widget_complete_messages_text: widget.fetch(:complete_text),
        },
      }

      params[:tool] = { name: tool_name, description: "With chat widget copy" } if tool_name
      params[:sql_query][:connector_id] = connector_id if connector_id
      params
    end

    def persisted_widget_configuration(tool_record)
      tool_record.configuration.slice(
        "tool_widget_icon",
        "tool_widget_running_mode",
        "tool_widget_running_interval_ms",
        "tool_widget_running_messages",
        "tool_widget_complete_messages",
      )
    end

    describe "GET /tools" do
      it "returns a successful response" do
        get admin_tools_path
        expect(response).to have_http_status(:ok)
      end

      it "displays the tools heading" do
        get admin_tools_path
        expect(response.body).to include("Tools")
      end

      it "shows plugin-provided builtin runtime tools in Headquarter" do
        headquarter = Operation.find_or_create_by!(name: Operation::HEADQUARTER_NAME) do |operation|
          operation.description = "System operation containing built-in agents and tools."
          operation.icon = "fa-solid fa-building-shield"
          operation.system = true
        end

        post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_tools_url }
        get admin_tools_path

        expect(response.body).to include("Built-in Tools")
        expect(response.body).to include("Schema Explorer")
      end

      it "displays the empty state when no tools exist" do
        get admin_tools_path
        expect(response.body).to include("No tools yet")
      end

      context "with existing tools" do
        it "lists tools in the selected version" do
          connector1 = create(:connector, :sql_database)
          connector2 = create(:connector, :sql_database)
          sq1 = create(:tools_sql_query, connector: connector1)
          sq2 = create(:tools_sql_query, connector: connector2)
          create(:tool, name: "HR Query", toolable: sq1)
          create(:tool, name: "Sales Query", toolable: sq2)

          get admin_tools_path
          expect(response.body).to include("HR Query")
          expect(response.body).to include("Sales Query")
        end
      end
    end

    describe "GET /tools/new" do
      it "returns a successful response" do
        get new_admin_tool_path
        expect(response).to have_http_status(:ok)
      end

      it "shows tool type selection" do
        get new_admin_tool_path
        expect(response.body).to include("SQL Query")
      end

      it "shows SQL Query form when type=sql_query" do
        create(:connector, :sql_database, :enabled)
        get new_admin_tool_path(type: "sql_query")
        expect(response.body).to include("Basic Information")
        expect(response.body).to include("Tool Configuration")
        expect(response.body).to include("SQL Database Connector")
        expect(response.body).not_to include("AI Schema Analysis")
      end
    end

    describe "POST /tools" do
      let!(:connector) { create(:connector, :sql_database, :enabled) }
      let(:auto_discovery_result) do
        Tools::SchemaDiscoverer::Result.new(
          success?: true,
          schema: { "objects" => [] },
          message: "Discovered 0 objects",
        )
      end
      let(:auto_discoverer) { instance_double(Tools::SchemaDiscoverer, call: auto_discovery_result) }

      let(:valid_params) do
        {
          tool_type: "sql_query",
          tool: { name: "Test Tool", description: "A test tool" },
          sql_query: { connector_id: connector.id },
        }
      end

      before do
        allow(Tools::SchemaDiscoverer).to receive(:new).and_return(auto_discoverer)
      end

      context "with valid params" do
        it "creates a new tool" do
          expect { post admin_tools_path, params: valid_params }
            .to change(Tool, :count).by(1)
        end

        it "discovers the schema automatically after create" do
          post admin_tools_path, params: valid_params

          expect(Tools::SchemaDiscoverer).to have_received(:new)
          expect(Tool.last.toolable.reload).to be_schema_discovered
        end

        it "generates instructions automatically after create" do
          auto_discovery_result = Tools::SchemaDiscoverer::Result.new(
            success?: true,
            schema: {
              "objects" => [
                { "type" => "table", "name" => "users", "columns" => [{ "name" => "id", "type" => "integer" }] },
              ],
            },
            message: "Discovered 1 object",
          )
          allow(auto_discoverer).to receive(:call).and_return(auto_discovery_result)

          post admin_tools_path, params: valid_params

          expect(Tool.last.toolable.reload.instructions).to include("users")
        end

        it "persists the shared chat widget configuration" do
          post admin_tools_path, params: sql_query_widget_params(
            connector_id: connector.id,
            tool_name: "Widget Tool",
            widget: {
              icon: "fa-solid fa-bolt",
              interval_ms: 1400,
              running_text: "Mapping the schema…\nDrafting the query…",
              complete_text: "Query plan ready.\nResults attached.",
            },
          )
          expect(persisted_widget_configuration(Tool.last)).to eq(
            expected_widget_configuration(
              icon: "fa-solid fa-bolt",
              interval_ms: 1400,
              running_messages: ["Mapping the schema…", "Drafting the query…"],
              complete_messages: ["Query plan ready.", "Results attached."],
            ),
          )
        end

        it "assigns the tool to the selected version" do
          post admin_tools_path, params: valid_params
          expect(Tool.last).to be_present
        end

        it "redirects to the tool show page" do
          post admin_tools_path, params: valid_params
          expect(response).to redirect_to(admin_tool_path(Tool.last))
        end

        it "sets a success flash message" do
          post admin_tools_path, params: valid_params
          expect(flash[:notice]).to eq("Tool created successfully.")
        end

        it "surfaces discovery alerts when auto-discovery fails after create" do
          failure_result = Tools::SchemaDiscoverer::Result.new(
            success?: false,
            schema: nil,
            message: "Connection refused",
          )
          allow(auto_discoverer).to receive(:call).and_return(failure_result)

          post admin_tools_path, params: valid_params

          expect(response).to redirect_to(admin_tool_path(Tool.last))
          expect(flash[:alert]).to eq("Connection refused")
        end
      end

      context "with invalid params" do
        it "does not create a tool without a name" do
          expect do
            post admin_tools_path, params: {
              tool_type: "sql_query",
              tool: { name: "" },
              sql_query: { connector_id: connector.id },
            }
          end.not_to change(Tool, :count)
        end

        it "re-renders the new form" do
          post admin_tools_path, params: {
            tool_type: "sql_query",
            tool: { name: "" },
            sql_query: { connector_id: connector.id },
          }
          expect(response).to have_http_status(:unprocessable_content)
        end
      end

      context "with an unknown tool_type" do
        it "responds with bad request" do
          post admin_tools_path, params: {
            tool_type: "nonexistent_tool_type_xyz",
            tool: { name: "Something" },
          }
          expect(response).to have_http_status(:bad_request)
        end
      end
    end

    describe "GET /tools/:id" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, name: "Show Tool", toolable: sq)
      end

      it "returns a successful response" do
        get admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
      end

      it "displays the tool details" do
        get admin_tool_path(tool)
        expect(response.body).to include("Show Tool")
        expect(response.body).to include("SQL Query")
        expect(response.body).to include(edit_widget_admin_tool_path(tool))
      end

      it "renders successfully when connector is missing" do
        tool.toolable.update!(connector_id: nil)

        get admin_tool_path(tool)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Not configured")
      end
    end

    describe "GET /tools/:id/edit" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, name: "Edit Tool", toolable: sq)
      end

      it "returns a successful response" do
        get edit_admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
      end

      it "displays the edit form" do
        get edit_admin_tool_path(tool)
        expect(response.body).to include("Edit Tool")
        expect(response.body).not_to include("Chat Widget")
        expect(response.body).not_to include("Write With AI")
        expect(response.body).not_to include("Your Prompt")
      end

      it "keeps widget editing on the dedicated page" do
        get edit_admin_tool_path(tool)

        expect(response.body).not_to include("While Executing")
        expect(response.body).not_to include("When Complete")
      end
    end

    describe "GET /tools/:id/edit_instructions" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, name: "Instruction Tool", toolable: sq)
      end

      it "returns a successful response" do
        get edit_instructions_admin_tool_path(tool)

        expect(response).to have_http_status(:ok)
      end

      it "shows only the instructions editor" do
        get edit_instructions_admin_tool_path(tool)

        expect(response.body).to include("Edit Instructions")
        expect(response.body).to include("Instructions")
        expect(response.body).not_to include("Basic Information")
        expect(response.body).not_to include("LLM Configuration")
        expect(response.body).not_to include("Tool Configuration")
      end

      it "binds the header submit button to the instructions form" do
        get edit_instructions_admin_tool_path(tool)

        document = response.parsed_body
        header_submit = document.at_css(".page-hero__action-group button[form='tool-instructions-form']")

        expect(header_submit).to be_present
        expect(header_submit.text.squish).to eq("Update Instructions")
      end

      it "returns not found when the tool type does not support instruction editing" do
        mcp_connector = create(:connector, :mcp_server, :enabled)
        mcp_tool = create(:tool, toolable: create(:tools_mcp_server, connector: mcp_connector))

        get edit_instructions_admin_tool_path(mcp_tool)

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "GET /tools/:id/edit_widget" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, name: "Widget Tool", toolable: sq)
      end

      it "returns a successful response" do
        get edit_widget_admin_tool_path(tool)

        expect(response).to have_http_status(:ok)
      end

      it "renders the widget-only form without the removed live preview" do
        get edit_widget_admin_tool_path(tool)

        expect(response.body).to include("Edit", "While Executing", "When Complete")
        expect(response.body).not_to include(
          "Live preview",
          "How the tool row will feel in chat",
          "Display Style",
          "Group Title",
        )
      end
    end

    describe "PATCH /tools/:id" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, name: "Old Name", toolable: sq)
      end

      context "with valid params" do
        it "updates the tool" do
          patch admin_tool_path(tool), params: {
            tool_type: "sql_query",
            tool: { name: "New Name" },
            sql_query: { connector_id: tool.toolable.connector_id },
          }
          expect(tool.reload.name).to eq("New Name")
        end

        it "updates the toolable when only plugin params are submitted over turbo stream" do
          replacement_connector = create(:connector, :sql_database)

          patch admin_tool_path(tool),
                params: {
                  sql_query: { connector_id: replacement_connector.id },
                },
                headers: { "ACCEPT" => Mime[:turbo_stream].to_s }

          expect(response).to redirect_to(admin_tool_path(tool))
          expect(tool.reload.toolable.connector_id).to eq(replacement_connector.id)
        end

        it "infers tool type from existing record when tool_type is absent" do
          patch admin_tool_path(tool), params: {
            tool: { name: "Inferred Type" },
            sql_query: { connector_id: tool.toolable.connector_id },
          }
          expect(tool.reload.name).to eq("Inferred Type")
          expect(response).to redirect_to(admin_tool_path(tool))
        end

        it "redirects to the tool page" do
          patch admin_tool_path(tool), params: {
            tool_type: "sql_query",
            tool: { name: "New Name" },
            sql_query: { connector_id: tool.toolable.connector_id },
          }
          expect(response).to redirect_to(admin_tool_path(tool.reload))
        end
      end

      context "with invalid params" do
        it "re-renders the edit form" do
          patch admin_tool_path(tool), params: {
            tool_type: "sql_query",
            tool: { name: "" },
            sql_query: { connector_id: tool.toolable.connector_id },
          }
          expect(response).to have_http_status(:unprocessable_content)
        end

        it "re-renders the instructions form when the instructions edit context fails" do
          patch admin_tool_path(tool), params: {
            tool: { name: "", edit_context: "instructions" },
            sql_query: { connector_id: tool.toolable.connector_id },
          }

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("Edit Instructions")
        end
      end
    end

    describe "PATCH /tools/:id/update_widget" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, name: "Widget Tool", toolable: sq)
      end

      it "updates the shared chat widget configuration" do
        patch update_widget_admin_tool_path(tool), params: sql_query_widget_params(
          widget: {
            icon: "fa-solid fa-compass",
            interval_ms: 1800,
            running_text: "Inspecting the vector store…\nRanking relevant chunks…",
            complete_text: "Search results are ready.",
          },
        )

        expect(persisted_widget_configuration(tool.reload)).to eq(
          expected_widget_configuration(
            icon: "fa-solid fa-compass",
            interval_ms: 1800,
            running_messages: ["Inspecting the vector store…", "Ranking relevant chunks…"],
            complete_messages: ["Search results are ready."],
          ),
        )
        expect(response).to redirect_to(admin_tool_path(tool))
      end

      it "re-renders the widget page when the widget configuration is invalid" do
        patch update_widget_admin_tool_path(tool), params: {
          tool_type: "sql_query",
          sql_query: { tool_widget_icon: "not-a-valid-icon" },
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Edit")
      end
    end

    describe "DELETE /tools/:id" do
      let!(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, toolable: sq)
      end

      it "destroys the tool" do
        expect { delete admin_tool_path(tool) }.to change(Tool, :count).by(-1)
      end

      it "redirects to the tools index" do
        delete admin_tool_path(tool)
        expect(response).to redirect_to(admin_tools_path)
      end
    end

    describe "PATCH /tools/:id/toggle" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, enabled: false, toolable: sq)
      end

      it "toggles the enabled status" do
        patch toggle_admin_tool_path(tool)
        expect(tool.reload.enabled).to be(true)
      end

      it "sets enabled notice when enabling" do
        patch toggle_admin_tool_path(tool)
        expect(flash[:notice]).to eq("Tool enabled.")
      end

      it "redirects to the tools index" do
        patch toggle_admin_tool_path(tool)
        expect(response).to redirect_to(admin_tools_path)
      end

      context "when tool is enabled" do
        let(:enabled_tool) do
          connector = create(:connector, :sql_database)
          sq = create(:tools_sql_query, connector:)
          create(:tool, enabled: true, toolable: sq)
        end

        it "disables the tool" do
          patch toggle_admin_tool_path(enabled_tool)
          expect(enabled_tool.reload.enabled).to be(false)
        end

        it "sets disabled notice" do
          patch toggle_admin_tool_path(enabled_tool)
          expect(flash[:notice]).to eq("Tool disabled.")
        end
      end
    end

    describe "POST /tools/:id/discover_schema" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, connector:)
        create(:tool, toolable: sq)
      end

      context "when discovery succeeds" do
        let(:schema) do
          { "objects" => [{ "type" => "table", "name" => "users",
                            "columns" => [{ "name" => "id", "type" => "integer" }], }] }
        end

        let(:success_result) do
          Tools::SchemaDiscoverer::Result.new(
            success?: true,
            schema:,
            message: "Discovered 1 objects",
          )
        end

        before do
          allow(Tools::SchemaDiscoverer).to receive(:new).and_return(
            instance_double(Tools::SchemaDiscoverer, call: success_result),
          )
        end

        it "updates the tool schema and redirects" do
          post discover_schema_admin_tool_path(tool)
          expect(response).to redirect_to(admin_tool_path(tool))
          follow_redirect!
          expect(response.body).to include("Database schema discovered successfully")
        end
      end

      context "when discovery fails" do
        let(:failure_result) do
          Tools::SchemaDiscoverer::Result.new(
            success?: false,
            schema: nil,
            message: "Connection refused",
          )
        end

        before do
          allow(Tools::SchemaDiscoverer).to receive(:new).and_return(
            instance_double(Tools::SchemaDiscoverer, call: failure_result),
          )
        end

        it "redirects with an error alert" do
          post discover_schema_admin_tool_path(tool)
          expect(response).to redirect_to(admin_tool_path(tool))
          follow_redirect!
          expect(response.body).to include("Connection refused")
        end
      end
    end

    describe "GET /tools/:id/edit_visibility" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, :with_schema, connector:)
        create(:tool, toolable: sq)
      end

      it "returns a successful response" do
        get edit_visibility_admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
      end

      it "displays the visibility form" do
        get edit_visibility_admin_tool_path(tool)
        expect(response.body).to include("Table Visibility")
      end

      context "when schema has not been discovered" do
        let(:tool_no_schema) do
          connector = create(:connector, :sql_database)
          sq = create(:tools_sql_query, connector:)
          create(:tool, toolable: sq)
        end

        it "redirects to the tool show page" do
          get edit_visibility_admin_tool_path(tool_no_schema)
          expect(response).to redirect_to(admin_tool_path(tool_no_schema))
        end
      end
    end

    describe "PATCH /tools/:id/update_visibility" do
      let(:tool) do
        connector = create(:connector, :sql_database)
        sq = create(:tools_sql_query, :with_schema, connector:)
        create(:tool, toolable: sq)
      end

      it "updates selected objects" do
        patch update_visibility_admin_tool_path(tool), params: {
          sql_query: { selected_objects: ["users"] },
        }
        expect(response).to redirect_to(admin_tool_path(tool))
        expect(tool.toolable.reload.selected_object_names).to eq(["users"])
      end

      it "clears all selected objects when none are checked" do
        patch update_visibility_admin_tool_path(tool), params: { sql_query: {} }
        expect(response).to redirect_to(admin_tool_path(tool))
        expect(tool.toolable.reload.selected_object_names).to eq([])
      end
    end
  end

  describe "MCP Server tools" do
    let!(:mcp_connector) { create(:connector, :mcp_server, :enabled) }

    describe "GET /tools/new with type=mcp_server" do
      it "shows MCP Server form" do
        get new_admin_tool_path(type: "mcp_server")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("MCP Server Connector")
      end
    end

    describe "POST /tools (MCP Server)" do
      let(:valid_params) do
        {
          tool_type: "mcp_server",
          tool: { name: "MCP Test Tool", description: "An MCP tool" },
          mcp_server: { connector_id: mcp_connector.id },
        }
      end

      it "creates a new MCP Server tool" do
        expect { post admin_tools_path, params: valid_params }
          .to change(Tool, :count).by(1)
      end

      it "redirects to the tool show page" do
        post admin_tools_path, params: valid_params
        expect(response).to redirect_to(admin_tool_path(Tool.last))
      end

      it "does not create a tool without a name" do
        expect do
          post admin_tools_path, params: {
            tool_type: "mcp_server",
            tool: { name: "" },
            mcp_server: { connector_id: mcp_connector.id },
          }
        end.not_to change(Tool, :count)
      end
    end

    describe "GET /tools/:id (MCP Server)" do
      let(:tool) do
        mcp = create(:tools_mcp_server, connector: mcp_connector)
        create(:tool, name: "MCP Show Tool", toolable: mcp)
      end

      it "returns a successful response" do
        get admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("MCP Show Tool")
        expect(response.body).to include("MCP Server")
      end

      it "renders successfully when connector is missing" do
        tool.toolable.update!(connector_id: nil)

        get admin_tool_path(tool)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Not configured")
      end
    end

    describe "GET /tools/:id/edit (MCP Server)" do
      let(:tool) do
        mcp = create(:tools_mcp_server, connector: mcp_connector)
        create(:tool, name: "MCP Edit Tool", toolable: mcp)
      end

      it "returns a successful response" do
        get edit_admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("MCP Server Connector")
      end
    end

    describe "PATCH /tools/:id (MCP Server)" do
      let(:tool) do
        mcp = create(:tools_mcp_server, connector: mcp_connector)
        create(:tool, name: "Old MCP Name", toolable: mcp)
      end

      it "updates the tool" do
        patch admin_tool_path(tool), params: {
          tool_type: "mcp_server",
          tool: { name: "New MCP Name" },
          mcp_server: { connector_id: mcp_connector.id },
        }
        expect(tool.reload.name).to eq("New MCP Name")
        expect(response).to redirect_to(admin_tool_path(tool.reload))
      end
    end

    describe "POST /tools/:id/discover_schema (MCP Server)" do
      let(:tool) do
        mcp = create(:tools_mcp_server, connector: mcp_connector)
        create(:tool, toolable: mcp)
      end

      context "when discovery succeeds" do
        let(:success_result) do
          Tools::McpToolDiscoverer::Result.new(
            success?: true,
            tools: [{ "name" => "read_file", "description" => "Read file" }],
            message: "Discovered 1 tool(s)",
          )
        end

        before do
          allow(Tools::McpToolDiscoverer).to receive(:new).and_return(
            instance_double(Tools::McpToolDiscoverer, call: success_result),
          )
        end

        it "updates the tool and redirects" do
          post discover_schema_admin_tool_path(tool)
          expect(response).to redirect_to(admin_tool_path(tool))
          expect(tool.toolable.reload.discovered_tools).to eq([{ "name" => "read_file",
                                                                 "description" => "Read file", }])
        end
      end

      context "when discovery fails" do
        let(:failure_result) do
          Tools::McpToolDiscoverer::Result.new(
            success?: false, tools: [], message: "Connection refused",
          )
        end

        before do
          allow(Tools::McpToolDiscoverer).to receive(:new).and_return(
            instance_double(Tools::McpToolDiscoverer, call: failure_result),
          )
        end

        it "redirects with an error alert" do
          post discover_schema_admin_tool_path(tool)
          expect(response).to redirect_to(admin_tool_path(tool))
          follow_redirect!
          expect(response.body).to include("Connection refused")
        end
      end
    end

    describe "GET /tools/:id/edit_visibility (MCP Server)" do
      let(:tool) do
        mcp = create(:tools_mcp_server, :with_tools, connector: mcp_connector)
        create(:tool, toolable: mcp)
      end

      it "returns a successful response" do
        get edit_visibility_admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Tool Visibility")
      end

      context "when tools have not been discovered" do
        let(:tool_no_discovery) do
          mcp = create(:tools_mcp_server, connector: mcp_connector)
          create(:tool, toolable: mcp)
        end

        it "redirects to the tool show page" do
          get edit_visibility_admin_tool_path(tool_no_discovery)
          expect(response).to redirect_to(admin_tool_path(tool_no_discovery))
        end
      end
    end

    describe "PATCH /tools/:id/update_visibility (MCP Server)" do
      let(:tool) do
        mcp = create(:tools_mcp_server, :with_tools, connector: mcp_connector)
        create(:tool, toolable: mcp)
      end

      it "updates selected tools" do
        patch update_visibility_admin_tool_path(tool), params: {
          mcp_server: { selected_tools: ["read_file"] },
        }
        expect(response).to redirect_to(admin_tool_path(tool))
        expect(tool.toolable.reload.selected_tool_names).to eq(["read_file"])
      end

      it "clears all selected tools when none are checked" do
        patch update_visibility_admin_tool_path(tool), params: { mcp_server: {} }
        expect(response).to redirect_to(admin_tool_path(tool))
        expect(tool.toolable.reload.selected_tool_names).to eq([])
      end
    end
  end

  describe "GET /tools/model_options" do
    it "returns a response with no connector" do
      get model_options_admin_agents_path,
          params: { frame_id: "tool_model_select", field_prefix: "sql_query" }
      expect(response).to have_http_status(:ok)
    end

    it "returns a response for a non-LLM connector" do
      connector = create(:connector, :sql_database, :enabled)
      get model_options_admin_agents_path,
          params: { connector_id: connector.id, frame_id: "tool_model_select", field_prefix: "sql_query" }
      expect(response).to have_http_status(:ok)
    end

    it "returns models for an LLM connector" do
      connector = create(:connector, :llm_provider, :enabled)
      get model_options_admin_agents_path,
          params: { connector_id: connector.id, frame_id: "tool_model_select", field_prefix: "sql_query" }
      expect(response).to have_http_status(:ok)
    end

    it "passes selected_model_id when provided" do
      connector = create(:connector, :llm_provider, :enabled)
      get model_options_admin_agents_path,
          params: {
            connector_id: connector.id, selected_model_id: "gpt-4",
            frame_id: "tool_model_select", field_prefix: "sql_query",
          }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "RAG Query tools" do
    let(:sql_connector) { create(:connector, :sql_database, :enabled) }
    let(:llm_connector) { create(:connector, :llm_provider, :enabled) }

    describe "GET /tools/new with type=rag_query" do
      it "shows RAG Query form" do
        get new_admin_tool_path(type: "rag_query")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Chunks Table")
        expect(response.body).to include("Documents Table")
      end

      it "renders distance method options from shared constants" do
        get new_admin_tool_path(type: "rag_query")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Cosine")
        expect(response.body).to include("Inner Product")
      end
    end

    describe "POST /tools (RAG Query)" do
      let(:valid_params) do
        {
          tool_type: "rag_query",
          tool: { name: "KB Search", description: "Search knowledge base", enabled: false },
          rag_query: {
            connector_id: sql_connector.id,
            chunks_table: "chunks",
            documents_table: "documents",
            embedding_field: "embedding",
            chunk_content_field: "content",
            document_reference_field: "document_id",
            distance_method: "cosine",
            max_distance: "0.8",
            results_limit: "10",
            llm_connector_id: llm_connector.id,
            model_id: "text-embedding-3-small",
            document_fields: ["title", "url"],
          },
        }
      end

      it "creates a new RAG Query tool" do
        expect { post admin_tools_path, params: valid_params }
          .to change(Tool, :count).by(1)
      end

      it "redirects to the tool show page" do
        post admin_tools_path, params: valid_params
        expect(response).to redirect_to(admin_tool_path(Tool.last))
      end

      it "does not create a tool without a name" do
        invalid_params = valid_params.deep_merge(tool: { name: "" })
        expect { post admin_tools_path, params: invalid_params }
          .not_to change(Tool, :count)
      end
    end

    describe "GET /tools/:id (RAG Query)" do
      let(:rag_query) { create(:tools_rag_query, :with_llm, connector: sql_connector) }
      let(:tool) { create(:tool, name: "RAG Tool", toolable: rag_query) }

      it "returns a successful response" do
        get admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("RAG Tool")
        expect(response.body).to include("RAG Query")
      end

      it "renders successfully when connector is missing" do
        tool.toolable.update!(connector_id: nil)

        get admin_tool_path(tool)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Not configured")
      end
    end

    describe "GET /tools/:id/edit (RAG Query)" do
      let(:rag_query) { create(:tools_rag_query, connector: sql_connector) }
      let(:tool) { create(:tool, name: "RAG Edit Tool", toolable: rag_query) }

      it "returns a successful response" do
        get edit_admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Edit Tool")
      end
    end

    describe "PATCH /tools/:id (RAG Query)" do
      let(:rag_query) { create(:tools_rag_query, connector: sql_connector) }
      let(:tool) { create(:tool, name: "RAG Update Tool", toolable: rag_query) }
      let(:update_params) do
        {
          tool_type: "rag_query",
          tool: { name: "Updated RAG Tool" },
          rag_query: {
            connector_id: sql_connector.id,
            chunks_table: "new_chunks",
            documents_table: "new_documents",
            embedding_field: "embedding",
            chunk_content_field: "content",
            document_reference_field: "document_id",
            distance_method: "l2",
            results_limit: "20",
            document_fields: ["title"],
          },
        }
      end

      it "updates the tool and redirects" do
        patch admin_tool_path(tool), params: update_params
        tool.reload
        rag_query.reload
        expect(response).to redirect_to(admin_tool_path(tool))
        expect(tool.name).to eq("Updated RAG Tool")
        expect(rag_query.chunks_table).to eq("new_chunks")
        expect(rag_query.distance_method).to eq("l2")
      end
    end

    describe "POST /tools/:id/discover_schema (RAG Query)" do
      let(:rag_query) { create(:tools_rag_query, connector: sql_connector) }
      let(:tool) { create(:tool, name: "RAG Discover", toolable: rag_query) }

      context "when discovery succeeds" do
        let(:schema) do
          {
            "objects" => [
              { "type" => "table", "name" => "chunks", "columns" => [] },
              { "type" => "table", "name" => "documents", "columns" => [] },
            ],
          }
        end

        before do
          result = instance_double(Tools::SchemaDiscoverer::Result, success?: true, schema:)
          allow_any_instance_of(Tools::SchemaDiscoverer).to receive(:call).and_return(result) # rubocop:disable RSpec/AnyInstance
        end

        it "updates the tool schema and redirects" do
          post discover_schema_admin_tool_path(tool)
          expect(response).to redirect_to(admin_tool_path(tool))
          expect(rag_query.reload.schema_discovered_at).to be_present
        end
      end

      context "when discovery fails" do
        before do
          result = instance_double(Tools::SchemaDiscoverer::Result, success?: false,
                                                                    message: "Connection failed",)
          allow_any_instance_of(Tools::SchemaDiscoverer).to receive(:call).and_return(result) # rubocop:disable RSpec/AnyInstance
        end

        it "redirects with an error alert" do
          post discover_schema_admin_tool_path(tool)
          expect(response).to redirect_to(admin_tool_path(tool))
          expect(flash[:alert]).to include("Connection failed")
        end
      end
    end

    describe "GET /tools/:id/edit_visibility (RAG Query)" do
      it "redirects when schema is not discovered" do
        rag_no_schema = create(:tools_rag_query, connector: sql_connector)
        tool_no_schema = create(:tool, name: "RAG No Schema", toolable: rag_no_schema)

        get edit_visibility_admin_tool_path(tool_no_schema)
        expect(response).to redirect_to(admin_tool_path(tool_no_schema))
      end
    end
  end

  describe "RAG tools" do
    let(:rag_flow) { create(:rag_flow, :with_steps) }

    describe "GET /tools/new with type=rag_flow" do
      it "shows RAG form" do
        get new_admin_tool_path(type: "rag_flow")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Rag Flow")
      end

      it "renders distance method options from shared constants" do
        get new_admin_tool_path(type: "rag_flow")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Cosine")
      end
    end

    describe "POST /tools (RAG)" do
      let(:valid_params) do
        {
          tool_type: "rag_flow",
          tool: { name: "Flow Search", description: "Search via flow", enabled: false },
          rag_flow: {
            rag_flow_id: rag_flow.id,
            distance_method: "cosine",
            max_distance: "0.8",
            results_limit: "10",
          },
        }
      end

      it "creates a new RAG tool" do
        expect do
          post admin_tools_path, params: valid_params
        end.to change(Tool, :count).by(1)
        expect(response).to redirect_to(admin_tool_path(Tool.last))
      end
    end

    describe "GET /tools/:id (RAG)" do
      let(:base_rag_flow) { create(:rag_flow, :with_steps) }
      let(:rag_flow_tool) { create(:tools_rag_flow, rag_flow: base_rag_flow) }
      let(:tool) { create(:tool, name: "Flow Search", toolable: rag_flow_tool) }

      it "shows the RAG tool" do
        get admin_tool_path(tool)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("RAG")
        expect(response.body).to include("Configuration")
      end

      it "renders successfully when rag flow is missing" do
        tool
        base_rag_flow.destroy!

        get admin_tool_path(tool)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Not configured")
      end
    end
  end

  describe "GET /tools/schema_analysis_model_options" do
    it "returns a response with no connector" do
      get model_options_admin_agents_path,
          params: {
            frame_id: "schema_analysis_model_select", field_prefix: "sql_query",
            field_name: "schema_analysis_model_id", required: "false",
          }
      expect(response).to have_http_status(:ok)
    end

    it "returns a response for a non-LLM connector" do
      connector = create(:connector, :sql_database, :enabled)
      get model_options_admin_agents_path,
          params: {
            connector_id: connector.id, frame_id: "schema_analysis_model_select",
            field_prefix: "sql_query", field_name: "schema_analysis_model_id", required: "false",
          }
      expect(response).to have_http_status(:ok)
    end

    it "returns models for an LLM connector" do
      connector = create(:connector, :llm_provider, :enabled)
      get model_options_admin_agents_path,
          params: {
            connector_id: connector.id, frame_id: "schema_analysis_model_select",
            field_prefix: "sql_query", field_name: "schema_analysis_model_id", required: "false",
          }
      expect(response).to have_http_status(:ok)
    end

    it "passes selected_model_id when provided" do
      connector = create(:connector, :llm_provider, :enabled)
      get model_options_admin_agents_path,
          params: {
            connector_id: connector.id, selected_model_id: "gpt-4",
            frame_id: "schema_analysis_model_select", field_prefix: "sql_query",
            field_name: "schema_analysis_model_id", required: "false",
          }
      expect(response).to have_http_status(:ok)
    end
  end
end
