# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agents" do
  describe "GET /agents" do
    it "returns a successful response" do
      get admin_agents_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "nested routes" do
    describe "GET /agents" do
      it "returns a successful response" do
        get admin_agents_path
        expect(response).to have_http_status(:ok)
      end

      it "displays the agents heading" do
        get admin_agents_path
        expect(response.body).to include("Agents")
      end

      it "counts builtin runtime tools on builtin agent cards" do
        headquarter = Operation.find_or_create_by!(name: Operation::HEADQUARTER_NAME) do |operation|
          operation.description = "System operation containing built-in agents and tools."
          operation.icon = "fa-solid fa-building-shield"
          operation.system = true
        end
        BuiltinAgents::Synchronizer.ensure_present!(keys: ["tool_designer"])
        builtin_agent = Agent.find_builtin_by_key("tool_designer")
        post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_agents_url }

        get admin_agents_path

        document = response.parsed_body
        card = document.at_css(%(a[href="#{admin_agent_path(builtin_agent)}"]))

        expect(card).to be_present
        expect(card.text).to include("8 tools")
      end

      it "displays the empty state when no agents exist" do
        get admin_agents_path
        expect(response.body).to include("No agents yet")
      end

      context "with existing agents" do
        it "lists agents" do
          create(:agent, name: "People Query Agent")
          create(:agent, name: "Sales Report Agent")
          get admin_agents_path
          expect(response.body).to include("People Query Agent")
          expect(response.body).to include("Sales Report Agent")
        end

        it "ensures builtin agents when Headquarter is active" do
          headquarter = Operation.find_or_create_by!(name: Operation::HEADQUARTER_NAME) do |operation|
            operation.description = "System operation containing built-in agents and tools."
            operation.icon = "fa-solid fa-building-shield"
            operation.system = true
          end
          allow(BuiltinAgents::Synchronizer).to receive(:ensure_present!)

          post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_agents_url }
          get admin_agents_path

          expect(BuiltinAgents::Synchronizer).to have_received(:ensure_present!)
        end
      end

      context "with operation scoping" do
        it "only shows agents belonging to the current operation" do
          operation = create(:operation)
          other_operation = create(:operation)
          create(:agent, name: "Scoped Agent", operation:)
          create(:agent, name: "Other Agent", operation: other_operation)
          post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_agents_url }
          get admin_agents_path
          expect(response.body).to include("Scoped Agent")
          expect(response.body).not_to include("Other Agent")
        end
      end
    end

    describe "GET /agents/new" do
      it "returns a successful response" do
        get new_admin_agent_path
        expect(response).to have_http_status(:ok)
      end

      it "shows the agent form" do
        get new_admin_agent_path
        expect(response.body).to include("New Agent")
        expect(response.body).to include("Basic Information")
        expect(response.body).to include("Model Configuration")
        expect(response.body).not_to include("System Instructions")
        expect(response.body).not_to include("Input Parameters")
      end

      it "renders cancel and submit in the header and drops footer buttons" do
        get new_admin_agent_path

        document = response.parsed_body
        header_back = document.at_css(".page-hero__action-group a[href='#{admin_agents_path}']")
        header_submit = document.at_css(".page-hero__action-group button[form='agent-form']")

        expect(header_back).to be_present
        expect(header_back.text.squish).to eq("Back to Agents")
        expect(header_submit).to be_present
        expect(header_submit.text.squish).to eq("Create Agent")
        footer_buttons = document.css("form#agent-form .btn").map { |node| node.text.squish }

        expect(footer_buttons).not_to include("Back", "Create Agent")
      end

      it "renders agent type as a dropdown populated from builtin agent types" do
        get new_admin_agent_path

        document = response.parsed_body
        select = document.at_css("select[name='agent[agent_type]']")

        expect(select).to be_present
        expect(document.at_css("input[name='agent[agent_type]']")).to be_nil
        expect(select.css("option").pluck("value")).to include("general", "mission_designer")
      end

      it "selects General by default" do
        get new_admin_agent_path

        document = response.parsed_body
        select = document.at_css("select[name='agent[agent_type]']")
        selected_option = select.at_css("option[selected]")

        expect(selected_option).to be_present
        expect(selected_option["value"]).to eq(AgentConfiguration::DEFAULT_AGENT_TYPE)
      end

      it "defaults the LLM source to system preference" do
        get new_admin_agent_path

        document = response.parsed_body
        select = document.at_css("select[name='agent[llm_config_source]']")
        selected_option = select.at_css("option[selected]")

        expect(selected_option).to be_present
        expect(selected_option["value"]).to eq("system_preference")
      end
    end

    describe "POST /agents" do
      let(:llm_connector) { create(:connector, :llm_provider, :enabled) }
      let(:valid_params) do
        {
          agent: {
            name: "Test Agent",
            description: "A test agent",
            instructions: "Be helpful",
            model_id: "gpt-4.1",
            temperature: 0.7,
            enabled: true,
            llm_connector_id: llm_connector.id,
          },
        }
      end

      context "with valid params" do
        it "creates a new agent" do
          expect do
            post admin_agents_path, params: valid_params
          end.to change(Agent, :count).by(1)
        end

        it "creates the agent" do
          post admin_agents_path, params: valid_params
          expect(Agent.last).to be_present
        end

        it "defaults the agent type to general when omitted" do
          post admin_agents_path, params: valid_params

          expect(Agent.last.configuration["agent_type"]).to eq(AgentConfiguration::DEFAULT_AGENT_TYPE)
        end

        it "defaults the LLM source to system preference when omitted" do
          post admin_agents_path, params: valid_params

          expect(Agent.last.configuration["llm_config_source"]).to eq("system_preference")
        end

        it "redirects to the agent show page" do
          post admin_agents_path, params: valid_params
          expect(response).to redirect_to(admin_agent_path(Agent.last))
        end

        it "sets a success flash message" do
          post admin_agents_path, params: valid_params
          expect(flash[:notice]).to eq("Agent created successfully.")
        end

        it "parses input_schema json when provided" do
          post admin_agents_path, params: {
            agent: valid_params[:agent].merge(
              input_schema: '[{"variable_name":"name","label":"Name","field_type":"string"}]',
            ),
          }

          expect(Agent.last.input_schema.first["variable_name"]).to eq("name")
        end

        it "falls back to an empty input_schema for invalid json" do
          post admin_agents_path, params: {
            agent: valid_params[:agent].merge(input_schema: "not-valid-json"),
          }

          expect(Agent.last.input_schema).to eq([])
        end

        it "persists thinking and custom llm params" do
          post admin_agents_path, params: {
            agent: valid_params[:agent].merge(
              thinking_effort: "medium",
              thinking_budget: 512,
              custom_llm_params: '{"top_p":0.9}',
            ),
          }

          agent = Agent.last

          expect(agent.thinking_effort).to eq("medium")
          expect(agent.thinking_budget).to eq(512)
          expect(agent.custom_llm_params).to eq({ "top_p" => 0.9 })
        end
      end

      context "with invalid params" do
        it "does not create an agent without a name" do
          expect do
            post admin_agents_path,
                 params: { agent: valid_params[:agent].merge(name: "") }
          end.not_to change(Agent, :count)
        end

        it "re-renders the new form" do
          post admin_agents_path,
               params: { agent: valid_params[:agent].merge(name: "") }
          expect(response).to have_http_status(:unprocessable_content)
        end

        it "re-renders when custom llm params are invalid" do
          post admin_agents_path,
               params: { agent: valid_params[:agent].merge(custom_llm_params: "not-json") }

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("must be valid JSON")
        end
      end

      context "with tools" do
        let!(:tool) do
          connector = create(:connector, :sql_database, :enabled)
          sql_query = create(:tools_sql_query, connector:)
          create(:tool, :enabled, toolable: sql_query)
        end

        it "assigns tools to the agent" do
          post admin_agents_path, params: {
            agent: valid_params[:agent].merge(assigned_tool_ids: [tool.id]),
          }

          agent = Agent.last
          expect(agent.assigned_tools).to include(tool)
        end
      end
    end

    describe "GET /agents/:id" do
      let(:agent) { create(:agent, name: "Show Agent") }
      let(:description) { "Coordinates runtime behavior for the current operation" }
      let(:input_parameter_schema) do
        [{ "variable_name" => "account_id", "field_type" => "string", "label" => "Account ID", "required" => true }]
      end

      before do
        agent.update!(description:, thinking_effort: "high", thinking_budget: 42)
      end

      it "returns a successful response" do
        get admin_agent_path(agent)
        expect(response).to have_http_status(:ok)
      end

      it "displays the agent details" do
        get admin_agent_path(agent)
        expect(response.body).to include("Show Agent")
        expect(response.body).to include("Configuration")
      end

      it "renders the shared compact header with the agent name inline" do
        get admin_agent_path(agent)

        document = response.parsed_body
        hero = document.at_css(".page-hero__heading")

        expect(hero).to be_present
        expect(hero.at_css(".page-hero__title-badge")&.text).to include("Agent")
        expect(hero.at_css(".page-hero__record-title")&.text).to include(agent.name)
      end

      it "drops header description copy and the old meta row" do
        get admin_agent_path(agent)

        document = response.parsed_body
        hero = document.at_css(".page-hero__heading")

        expect(document.at_css(".page-hero__text")).to be_nil
        expect(hero.at_css(".page-hero__meta")).to be_nil
        expect(response.body).not_to include(description)
      end

      it "keeps delete and edit in separate grouped controls" do
        get admin_agent_path(agent)

        document = response.parsed_body
        action_groups = document.css(".page-hero__action-group").map do |group|
          group.css("a, button").map { |node| node.text.squish }
        end

        expect(action_groups).to eq([["Delete"], ["Edit"]])
        expect(document.css(".page-hero__control-separator").size).to eq(1)
        expect(document.at_css(".page-hero__action-group a.btn-primary")&.text).to include("Edit")
      end

      it "renders the show sections in the requested order" do
        get admin_agent_path(agent)

        document = response.parsed_body
        section_headings = document.css(".card-header h3").map { |node| node.text.squish }

        expect(section_headings).to eq(
          [
            "Configuration",
            "Input Parameters",
            "Tools",
            "Sub-Agents",
            "Skill Catalogs",
            "Capabilities",
            "System Instructions",
          ],
        )
      end

      it "shows reasoning controls in the configuration card and omits created metadata" do
        get admin_agent_path(agent)

        document = response.parsed_body
        configuration_card = document.css(".card").find do |card|
          card.at_css(".card-header h3")&.text&.squish == "Configuration"
        end

        expect(configuration_card).to be_present
        expect(configuration_card.text).to include("Reasoning", "High", "Thinking Budget", "42")
        expect(configuration_card.text).not_to include("Created")
      end

      it "shows the input parameters card even when the agent has no schema" do
        get admin_agent_path(agent)

        expect(response.body).to include("Input Parameters")
        expect(response.body).to include("No input parameters defined.")
        expect(response.body).to include("Add")
      end

      it "shows defined input parameters in their dedicated card with the compact row UI" do
        agent.update!(input_schema: input_parameter_schema)

        get admin_agent_path(agent)

        document = response.parsed_body
        input_parameters_card = document.css(".card").find do |card|
          card.at_css(".card-header h3")&.text&.squish == "Input Parameters"
        end

        expect(input_parameters_card).to be_present
        expect(input_parameters_card.text).to include("account_id", "String", "Required", "Account ID")
        expect(input_parameters_card.at_css(".entity-card__icon")).to be_present
      end

      it "renders dedicated edit buttons for configuration and instructions" do
        get admin_agent_path(agent)

        document = response.parsed_body
        configuration_card = document.css(".card").find do |card|
          card.at_css(".card-header h3")&.text&.squish == "Configuration"
        end
        instructions_card = document.css(".card").find do |card|
          card.at_css(".card-header h3")&.text&.squish == "System Instructions"
        end
        instructions_edit_link = instructions_card.at_css(
          "a[href='#{edit_instructions_admin_agent_path(agent)}']",
        )

        expect(configuration_card.at_css("a[href='#{edit_admin_agent_path(agent)}']")&.text&.squish).to eq("Edit")
        expect(instructions_edit_link&.text&.squish).to eq("Edit")
      end

      it "renders the system instructions preview with smaller typography" do
        get admin_agent_path(agent)

        expect(response.body).to include("text-[11px]")
      end

      it "shows builtin tools configured on builtin agents" do
        BuiltinAgents::Synchronizer.ensure_present!(keys: ["mission_designer"])
        builtin_agent = Agent.find_builtin_by_key("mission_designer")

        get admin_agent_path(builtin_agent)

        expect(response.body).to include("Read Mission Flow")
        expect(response.body).to include("Built-in")
      end

      it "shows fallback metadata for unknown runtime tools" do
        agent.update!(runtime_tool_keys: ["missing_runtime_tool"])

        get admin_agent_path(agent)

        expect(response.body).to include("missing_runtime_tool")
        expect(response.body).to include("Missing built-in tool definition.")
      end
    end

    describe "GET /agents/:id/edit" do
      let(:agent) { create(:agent) }

      it "returns a successful response" do
        get edit_admin_agent_path(agent)
        expect(response).to have_http_status(:ok)
      end

      it "shows the edit form" do
        get edit_admin_agent_path(agent)
        expect(response.body).to include("Edit Agent")
      end

      it "shows the record title inline in the shared header" do
        get edit_admin_agent_path(agent)

        document = response.parsed_body

        expect(document.at_css(".page-hero__title-badge")&.text).to include("Edit Agent")
        expect(document.at_css(".page-hero__record-title")&.text).to include(agent.name)
      end

      it "renders back and submit in the header instead of footer actions" do
        get edit_admin_agent_path(agent)

        document = response.parsed_body
        header_back = document.at_css(".page-hero__action-group a[href='#{admin_agent_path(agent)}']")
        header_submit = document.at_css(".page-hero__action-group button[form='agent-form']")

        expect(header_back).to be_present
        expect(header_back.text.squish).to eq("Back to #{agent.name}")
        expect(header_submit).to be_present
        expect(header_submit.text.squish).to eq("Update Agent")
        footer_buttons = document.css("form#agent-form .btn").map { |node| node.text.squish }

        expect(footer_buttons).not_to include("Back", "Update Agent")
      end

      it "only shows configuration fields on the edit page" do
        get edit_admin_agent_path(agent)

        expect(response.body).to include("Basic Information")
        expect(response.body).to include("Model Configuration")
        expect(response.body).not_to include("System Instructions")
        expect(response.body).not_to include("Input Parameters")
      end

      it "stacks the configuration cards before the xl breakpoint" do
        get edit_admin_agent_path(agent)

        expect(response.body).to include("grid grid-cols-1 xl:grid-cols-2")
        expect(response.body).not_to include("grid grid-cols-1 lg:grid-cols-2")
      end
    end

    describe "GET /agents/:id/edit_instructions" do
      let(:agent) { create(:agent) }

      it "returns a successful response" do
        get edit_instructions_admin_agent_path(agent)
        expect(response).to have_http_status(:ok)
      end

      it "shows only the instructions editor" do
        get edit_instructions_admin_agent_path(agent)

        expect(response.body).to include("Edit Instructions")
        expect(response.body).to include("System Instructions")
        expect(response.body).not_to include("Basic Information")
        expect(response.body).not_to include("Model Configuration")
        expect(response.body).not_to include("Input Parameters")
      end

      it "binds the header submit button to the instructions form" do
        get edit_instructions_admin_agent_path(agent)

        document = response.parsed_body
        header_submit = document.at_css(".page-hero__action-group button[form='agent-instructions-form']")

        expect(header_submit).to be_present
        expect(header_submit.text.squish).to eq("Update Instructions")
      end
    end

    describe "PATCH /agents/:id" do
      let(:agent) { create(:agent, name: "Old Name") }

      context "with valid params" do
        it "updates the agent" do
          patch admin_agent_path(agent), params: { agent: { name: "New Name" } }
          expect(agent.reload.name).to eq("New Name")
        end

        it "updates input parameters from the show-page edit context" do
          patch admin_agent_path(agent), params: {
            agent: {
              edit_context: "input_parameters",
              input_schema: '[{"variable_name":"favorite_color","label":"Favorite Color","field_type":"string"}]',
            },
          }

          expect(response).to redirect_to(admin_agent_path(agent.reload))
          expect(agent.input_schema).to eq(
            [
              {
                "config" => {},
                "variable_name" => "favorite_color",
                "label" => "Favorite Color",
                "field_type" => "string",
                "required" => nil,
              },
            ],
          )
        end

        it "redirects to the agent page" do
          patch admin_agent_path(agent), params: { agent: { name: "New Name" } }
          expect(response).to redirect_to(admin_agent_path(agent.reload))
        end

        it "preserves the existing name when omitted and clears a blank input schema" do
          agent.update!(input_schema: [{ "variable_name" => "legacy", "label" => "Legacy", "field_type" => "string" }])

          patch admin_agent_path(agent), params: {
            agent: {
              description: "Updated description",
              input_schema: "",
            },
          }

          agent.reload
          expect(agent.name).to eq("Old Name")
          expect(agent.description).to eq("Updated description")
          expect(agent.input_schema).to eq([])
        end
      end

      context "with invalid params" do
        it "re-renders the edit form" do
          patch admin_agent_path(agent), params: { agent: { name: "" } }
          expect(response).to have_http_status(:unprocessable_content)
        end

        it "re-renders the instructions form when the instructions edit context fails" do
          patch admin_agent_path(agent), params: { agent: { name: "", edit_context: "instructions" } }

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("Edit Instructions")
        end

        it "re-renders the show page when the input parameter edit context fails" do
          patch admin_agent_path(agent), params: { agent: { name: "", edit_context: "input_parameters" } }

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("Input Parameters")
        end
      end
    end

    describe "DELETE /agents/:id" do
      let!(:agent) { create(:agent) }

      it "deletes the agent" do
        expect { delete admin_agent_path(agent) }.to change(Agent, :count).by(-1)
      end

      it "redirects to the agents index" do
        delete admin_agent_path(agent)
        expect(response).to redirect_to(admin_agents_path)
      end
    end

    describe "GET /agents/model_options" do
      it "returns a successful response without a connector" do
        get model_options_admin_agents_path,
            params: { frame_id: "agent_model_select", field_prefix: "agent" }
        expect(response).to have_http_status(:ok)
      end

      it "filters models to the connector's provider" do
        connector = create(:connector, :llm_provider, :enabled) # provider: openai
        create(:model, provider: "openai", name: "GPT-4o")
        create(:model, provider: "anthropic", name: "Claude 3")
        get model_options_admin_agents_path,
            params: { connector_id: connector.id, frame_id: "agent_model_select", field_prefix: "agent" }
        expect(response.body).to include("GPT-4o")
        expect(response.body).not_to include("Claude 3")
      end

      it "returns no models when no connector given" do
        create(:model, provider: "openai", name: "GPT-4o")
        create(:model, provider: "anthropic", name: "Claude 3")
        get model_options_admin_agents_path,
            params: { frame_id: "agent_model_select", field_prefix: "agent" }
        expect(response.body).not_to include("GPT-4o")
        expect(response.body).not_to include("Claude 3")
      end

      it "preserves the selected model when passed" do
        create(:model, provider: "openai", name: "GPT-4o", model_id: "gpt-4o")
        connector = create(:connector, :llm_provider, :enabled)
        get model_options_admin_agents_path,
            params: {
              connector_id: connector.id, selected_model_id: "gpt-4o",
              frame_id: "agent_model_select", field_prefix: "agent",
            }
        expect(response.body).to include("gpt-4o")
      end

      it "preserves llm-settings wiring when requested" do
        connector = create(:connector, :llm_provider, :enabled)
        create(:model, provider: "openai", name: "GPT-4o", model_id: "gpt-4o")

        get model_options_admin_agents_path,
            params: {
              connector_id: connector.id,
              frame_id: "agent_model_select",
              field_prefix: "agent",
              llm_settings: true,
            }

        expect(response.body).to include("data-llm-settings-target=\"modelFrame\"")
        expect(response.body).to include("turbo:frame-load-&gt;llm-settings#syncCapabilities")
        expect(response.body).to include("change-&gt;llm-settings#syncCapabilities")
      end
    end

    describe "GET /agents/embedding_model_options" do
      it "returns a successful response without a connector" do
        get embedding_model_options_admin_agents_path,
            params: { frame_id: "embed_model_select", field_prefix: "rag_query" }
        expect(response).to have_http_status(:ok)
      end

      it "filters models to those with embeddings output modality" do
        connector = create(:connector, :llm_provider, :enabled)
        create(:model, provider: "openai", name: "Embed Model",
                       model_id: "text-embedding-3-small",
                       modalities: { "input" => ["text"], "output" => ["embeddings"] },)
        create(:model, provider: "openai", name: "Chat Model",
                       model_id: "gpt-4o",
                       modalities: { "input" => ["text"], "output" => ["text"] },)
        get embedding_model_options_admin_agents_path,
            params: { connector_id: connector.id, frame_id: "embed_select", field_prefix: "rag_query" }
        expect(response.body).to include("Embed Model")
        expect(response.body).not_to include("Chat Model")
      end

      it "supports custom field_name" do
        get embedding_model_options_admin_agents_path,
            params: { frame_id: "embed_select", field_prefix: "system_preference", field_name: "embedding_model_id" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("embedding_model_id")
      end
    end

    describe "GET /agents/image_model_options" do
      it "returns a successful response without a connector" do
        get image_model_options_admin_agents_path,
            params: { frame_id: "image_model_select", field_prefix: "system_preference" }
        expect(response).to have_http_status(:ok)
      end

      it "filters models to those with image output modality" do
        connector = create(:connector, :llm_provider, :enabled)
        create(:model, provider: "openai", name: "Image Model",
                       model_id: "gpt-image-1",
                       modalities: { "input" => ["text"], "output" => ["image"] },)
        create(:model, provider: "openai", name: "Chat Model",
                       model_id: "gpt-4o",
                       modalities: { "input" => ["text"], "output" => ["text"] },)
        get image_model_options_admin_agents_path,
            params: { connector_id: connector.id, frame_id: "image_select", field_prefix: "system_preference" }
        expect(response.body).to include("Image Model")
        expect(response.body).not_to include("Chat Model")
      end

      it "supports custom field_name" do
        get image_model_options_admin_agents_path,
            params: { frame_id: "image_select", field_prefix: "system_preference", field_name: "image_model_id" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("image_model_id")
      end
    end

    describe "POST /agents/:id/add_tool" do
      let(:agent) { create(:agent) }
      let(:connector) { create(:connector, :sql_database, :enabled) }
      let(:sql_query) { create(:tools_sql_query, connector:) }
      let(:tool) { create(:tool, :enabled, toolable: sql_query) }

      it "assigns the tool to the agent" do
        post add_tool_admin_agent_path(agent), params: { tool_id: tool.id }
        expect(agent.reload.tool_ids).to include(tool.id)
      end

      it "redirects with a notice" do
        post add_tool_admin_agent_path(agent), params: { tool_id: tool.id }
        expect(response).to redirect_to(admin_agent_path(agent))
        expect(flash[:notice]).to eq(I18n.t("agents.tool_added"))
      end
    end

    describe "DELETE /agents/:id/remove_tool" do
      let(:agent) { create(:agent, :with_sql_tool) }

      it "removes the tool from the agent" do
        tool_id = agent.tool_ids.first
        delete remove_tool_admin_agent_path(agent), params: { tool_id: }
        expect(agent.reload.tool_ids).not_to include(tool_id)
      end

      it "redirects with a notice" do
        delete remove_tool_admin_agent_path(agent), params: { tool_id: agent.tool_ids.first }
        expect(response).to redirect_to(admin_agent_path(agent))
        expect(flash[:notice]).to eq(I18n.t("agents.tool_removed"))
      end
    end

    describe "POST /agents/:id/add_capability" do
      let(:agent) { create(:agent) }

      it "redirects to the capability edit page" do
        post add_capability_admin_agent_path(agent), params: { key: :chat_title_generator }
        expect(response).to redirect_to(edit_admin_agent_capability_path(agent, :chat_title_generator))
      end

      it "returns not found for an unknown capability" do
        post add_capability_admin_agent_path(agent), params: { key: :nonexistent }
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST /agents/:id/add_subagent" do
      let(:agent) { create(:agent) }
      let(:subagent) { create(:agent, :enabled) }

      it "assigns the sub-agent" do
        post add_subagent_admin_agent_path(agent), params: { subagent_id: subagent.id }
        expect(agent.reload.subagent_ids).to include(subagent.id)
      end

      it "redirects with a notice" do
        post add_subagent_admin_agent_path(agent), params: { subagent_id: subagent.id }
        expect(response).to redirect_to(admin_agent_path(agent))
        expect(flash[:notice]).to eq(I18n.t("agents.subagent_added"))
      end

      it "re-renders show when save fails" do
        allow_any_instance_of(Agent).to receive(:save).and_return(false) # rubocop:disable RSpec/AnyInstance
        post add_subagent_admin_agent_path(agent), params: { subagent_id: subagent.id }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "POST /agents/:id/add_skill_catalog" do
      let(:skill_catalog) { create(:skill_catalog) }
      let(:agent) { create(:agent, operation: skill_catalog.operation) }

      it "assigns the skill catalog" do
        post add_skill_catalog_admin_agent_path(agent), params: { skill_catalog_id: skill_catalog.id }

        expect(agent.reload.skill_catalog_ids).to include(skill_catalog.id)
      end

      it "redirects with a notice" do
        post add_skill_catalog_admin_agent_path(agent), params: { skill_catalog_id: skill_catalog.id }

        expect(response).to redirect_to(admin_agent_path(agent))
        expect(flash[:notice]).to eq(I18n.t("agents.skill_catalog_added"))
      end
    end

    describe "DELETE /agents/:id/remove_skill_catalog" do
      let(:skill_catalog) { create(:skill_catalog) }
      let(:agent) { create(:agent, operation: skill_catalog.operation) }

      before do
        agent.update!(skill_catalog_ids: [skill_catalog.id])
      end

      it "removes the skill catalog" do
        delete remove_skill_catalog_admin_agent_path(agent), params: { skill_catalog_id: skill_catalog.id }

        expect(agent.reload.skill_catalog_ids).to eq([])
      end

      it "redirects with a notice" do
        delete remove_skill_catalog_admin_agent_path(agent), params: { skill_catalog_id: skill_catalog.id }

        expect(response).to redirect_to(admin_agent_path(agent))
        expect(flash[:notice]).to eq(I18n.t("agents.skill_catalog_removed"))
      end
    end

    describe "DELETE /agents/:id/remove_subagent" do
      let(:agent) { create(:agent, :with_subagent) }

      it "removes the sub-agent" do
        sub_id = agent.subagent_ids.first
        delete remove_subagent_admin_agent_path(agent), params: { subagent_id: sub_id }
        expect(agent.reload.subagent_ids).not_to include(sub_id)
      end

      it "redirects with a notice" do
        delete remove_subagent_admin_agent_path(agent), params: { subagent_id: agent.subagent_ids.first }
        expect(response).to redirect_to(admin_agent_path(agent))
        expect(flash[:notice]).to eq(I18n.t("agents.subagent_removed"))
      end
    end

    describe "PATCH /agents/:id/toggle" do
      let(:agent) { create(:agent, enabled: true) }

      it "toggles the agent enabled state" do
        patch toggle_admin_agent_path(agent)
        expect(agent.reload.enabled?).to be(false)
      end

      it "redirects to the agents index" do
        patch toggle_admin_agent_path(agent)
        expect(response).to redirect_to(admin_agents_path)
      end

      it "shows a flash message when disabling" do
        patch toggle_admin_agent_path(agent)
        expect(flash[:notice]).to eq("Agent disabled.")
      end

      context "when agent is disabled" do
        let(:disabled_agent) { create(:agent, enabled: false) }

        it "enables the agent" do
          patch toggle_admin_agent_path(disabled_agent)
          expect(disabled_agent.reload.enabled?).to be(true)
        end

        it "shows enabled flash message" do
          patch toggle_admin_agent_path(disabled_agent)
          expect(flash[:notice]).to eq("Agent enabled.")
        end
      end
    end

    describe "POST /agents/:id/restore" do
      let!(:builtin_agent) do
        BuiltinAgents::Synchronizer.ensure_present!(keys: ["agent_alpha"])
        Agent.find_builtin_by_key("agent_alpha")
      end

      it "restores a builtin agent in Headquarter" do
        builtin_agent.update!(name: "Customized Agent Alpha")

        post restore_admin_agent_path(builtin_agent)

        expect(response).to redirect_to(admin_agent_path(builtin_agent.reload))
        expect(builtin_agent.reload.name).to eq("Agent Alpha")
      end

      it "restores a builtin agent when restore authorization is explicitly allowed" do
        builtin_agent.update!(name: "Customized Agent Alpha")
        allow(AgentPolicy).to receive(:new).and_wrap_original do |original, user, record|
          policy = original.call(user, record)
          allow(policy).to receive(:restore?).and_return(true) if record == builtin_agent
          policy
        end

        post restore_admin_agent_path(builtin_agent)

        expect(response).to redirect_to(admin_agent_path(builtin_agent.reload))
        expect(builtin_agent.reload.name).to eq("Agent Alpha")
      end

      it "raises not found for a non-builtin agent" do
        post restore_admin_agent_path(create(:agent))

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST /agents/restore_defaults" do
      it "refuses to restore all builtin agents outside Headquarter" do
        BuiltinAgents::Synchronizer.ensure_present!(keys: ["agent_alpha"])

        post restore_defaults_admin_agents_path

        expect(response).to redirect_to(root_path)
      end

      it "restores all builtin agents in Headquarter" do
        BuiltinAgents::Synchronizer.ensure_present!(keys: ["agent_alpha"])
        headquarter = Agent.find_builtin_by_key("agent_alpha").operation
        post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_agents_url }
        allow(BuiltinAgents::Synchronizer).to receive(:restore_all!)
          .and_return(BuiltinAgents::Synchronizer::Result.new(created_keys: [], restored_keys: ["agent_alpha"]))

        post restore_defaults_admin_agents_path

        expect(response).to redirect_to(admin_agents_path)
        expect(flash[:notice]).to eq(I18n.t("agents.restored_all", count: 1))
      end

      it "handles the zero-restored branch" do
        BuiltinAgents::Synchronizer.ensure_present!(keys: ["agent_alpha"])
        headquarter = Agent.find_builtin_by_key("agent_alpha").operation
        post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_agents_url }

        allow(BuiltinAgents::Synchronizer).to receive(:restore_all!)
          .and_return(BuiltinAgents::Synchronizer::Result.new(created_keys: [], restored_keys: []))

        post restore_defaults_admin_agents_path

        expect(response).to redirect_to(admin_agents_path)
        expect(flash[:notice]).to eq(I18n.t("agents.restored_all", count: 0))
      end
    end
  end
end
