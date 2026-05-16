# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard" do
  describe "GET /admin" do
    def parsed_response
      response.parsed_body
    end

    def sidebar_operation_name
      operation_section = parsed_response.css(".sidebar-section").find do |section|
        section.at_css(".sidebar-section-label")&.text&.strip == "Operation"
      end

      operation_name = operation_section&.at_css(".sidebar-operation-name")
      operation_name&.text&.strip
    end

    def sidebar_section_labels
      parsed_response.css(".sidebar-section-label").map { |node| node.text.strip }
    end

    def dashboard_operation_filter_label
      parsed_response.at_css(".dash-op-btn span")&.text&.strip
    end

    it "returns a successful response" do
      get admin_root_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the hero text before the radar visual" do
      get admin_root_path

      hero_children = parsed_response.at_css(".dash-banner-content")&.element_children || []
      hero_classes = hero_children.pluck("class")

      expect(hero_classes.index("dash-banner-text")).to be < hero_classes.index("dash-banner-visual")
    end

    it "renders a shared sticky dashboard header with the operation filter and no quick actions" do
      get admin_root_path

      hero = parsed_response.at_css(".page-hero.page-hero--sticky")

      expect(hero).to be_present
      expect(hero.text).to include("Dashboard")
      expect(hero.at_css(".dash-op-filter")).to be_present
      expect(parsed_response.at_css(".dash-quick-actions-bar")).to be_nil
      expect(hero.at_css(".page-hero__action-group")).to be_nil
    end

    it "renders the hero metrics section" do
      get admin_root_path
      expect(response.body).to include("Conversations")
      expect(response.body).to include("Token Usage")
    end

    it "renders the platform inventory" do
      get admin_root_path
      expect(response.body).to include("Platform Overview")
      expect(response.body).to include("Connectors")
      expect(response.body).to include("Agents")
      expect(response.body).to include("Channels")
    end

    it "renders the getting started section when db is empty" do
      get admin_root_path
      expect(response.body).to include("Get Started with Undercover Agents")
    end

    it "renders the activity feed" do
      get admin_root_path
      expect(response.body).to include("Recent Conversations")
      expect(response.body).to include("Recent Missions")
      expect(response.body).to include("Recent Tests")
    end

    it "does not render create buttons in empty recent activity panels" do
      get admin_root_path

      expect(response.body).not_to include("Start a Chat")
      expect(response.body).not_to include("Create Mission")
      expect(response.body).not_to include("Create Test Suite")
    end

    context "when system preference exists with no models configured" do
      before { create(:system_preference) }

      it "evaluates any_model_configured? with preference present" do
        get admin_root_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Get Started")
      end
    end

    context "when system preference has llm configured" do
      before { create(:system_preference, :configured) }

      it "does not show getting started when fully configured" do
        create(:agent)
        get admin_root_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when only builtin agents exist" do
      before do
        create(:system_preference, :configured)

        builtin_agent = create(
          :agent,
          builtin: true,
          builtin_key: "mission_designer",
          selectable: false,
        )
        chat = create(:chat, agent: builtin_agent)
        create(:message, chat:)
      end

      it "keeps the first agent step pending" do
        get admin_root_path

        step = parsed_response.css(".dashboard-step").find do |node|
          node.at_css(".dashboard-step-title")&.text&.strip == "Build Your First Agent"
        end

        expect(response.body).to include("Get Started with Undercover Agents")
        expect(step["class"]).to include("dashboard-step--pending")
      end
    end

    context "when activity data exists" do
      before do
        agent = create(:agent)
        chat = create(:chat, agent:)
        create(:message, chat:)
        create(:tool, :sql_query)
      end

      it "does not render the breakdown pie charts" do
        get admin_root_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Activity — Last 30 Days")
        expect(response.body).not_to include("Messages by Role")
        expect(response.body).not_to include("Connectors by Type")
        expect(response.body).not_to include("Tools by Type")
      end
    end

    it "includes the sidebar" do
      get admin_root_path
      expect(response.body).to include("Undercover Agents")
      expect(response.body).to include("sidebar")
    end

    it "does not render a tenant section in the sidebar" do
      get admin_root_path

      expect(sidebar_section_labels).not_to include("Tenant")
    end

    it "includes the theme toggle" do
      get admin_root_path
      expect(response.body).to include("theme")
    end

    context "with a previously selected operation" do
      let(:operation) { create(:operation, name: "Ops Beta") }

      it "resets the selected operation to the default on direct admin entry" do
        post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_agents_url }

        get admin_root_path

        expect(sidebar_operation_name).to eq(default_operation.name)
      end

      it "preserves the selected operation when navigating from another admin page" do
        post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_agents_url }

        get admin_root_path, headers: { "HTTP_REFERER" => admin_agents_url }

        expect(sidebar_operation_name).to eq(operation.name)
      end

      it "treats non-admin referrers as direct admin entry" do
        post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_agents_url }

        get admin_root_path, headers: { "HTTP_REFERER" => new_session_url }

        expect(sidebar_operation_name).to eq(default_operation.name)
        expect(response.body).to include("Get Started with Undercover Agents")
      end
    end

    context "with operation filter" do
      let(:operation) { create(:operation, name: "Ops Alpha") }

      before do
        create(:agent, operation:, name: "Ops Agent")
        create(:agent, name: "Other Agent")
      end

      it "renders the operation dropdown" do
        get admin_root_path
        expect(response.body).to include("All Operations")
        expect(response.body).to include("Ops Alpha")
      end

      it "filters by operation when param is present" do
        get admin_root_path, params: { operation: operation.slug }
        expect(response).to have_http_status(:ok)
      end

      it "shows global stats when no operation is selected" do
        get admin_root_path
        expect(response).to have_http_status(:ok)
      end

      it "keeps All Operations selected when explicitly requested from another admin page" do
        post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_agents_url }

        get admin_root_path, params: { operation: "all" }, headers: { "HTTP_REFERER" => admin_agents_url }

        expect(response).to have_http_status(:ok)
        expect(dashboard_operation_filter_label).to eq("All Operations")
      end

      it "keeps getting started visible when an operation is selected and setup is incomplete" do
        create(:connector, :llm_provider, :enabled, tenant: default_tenant)

        get admin_root_path, params: { operation: operation.slug }

        expect(response.body).to include("Get Started with Undercover Agents")
      end
    end
  end
end
