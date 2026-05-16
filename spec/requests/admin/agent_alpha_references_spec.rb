# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AgentAlphaReferences", :unauthenticated do
  let(:user) { create(:user, :admin, tenant: default_tenant) }
  let(:operation) { user.tenant.default_operation }

  before do
    create(:model, model_id: "gpt-4.1", provider: "openai")
    create(:system_preference, :configured, tenant: user.tenant)
    sign_in(user)
  end

  describe "GET /admin/agent_alpha/references" do
    context "with references across scopes" do
      it "returns operation-scoped mission results" do
        grouped_items, fixtures = scoped_reference_groups
        mission_items = grouped_items.dig("missions", "items")

        expect(response).to have_http_status(:ok)
        expect(mission_items).to include(
          mission_reference_item(fixtures.fetch(:visible_mission), mention: "#launch-plan"),
        )
        expect(mission_items).not_to include(hash_including("label" => fixtures.fetch(:hidden_mission_name)))
      end

      it "returns tool and skill results" do
        grouped_items, fixtures = scoped_reference_groups

        expect(grouped_items.dig("tools", "items")).to include(hash_including("id" => fixtures.fetch(:visible_tool).id))
        expect(grouped_items.dig("skills", "items")).to include(
          hash_including(
            "id" => fixtures.fetch(:visible_skill).id,
            "subtitle" => fixtures.fetch(:catalog).name,
          ),
        )
      end

      it "returns tenant-scoped client results" do
        grouped_items, fixtures = scoped_reference_groups

        expect(grouped_items.dig("clients", "items")).to include(client_reference_item(fixtures.fetch(:visible_client)))
        expect(grouped_items.dig("clients", "items")).not_to include(
          hash_including("label" => fixtures.fetch(:hidden_client_name)),
        )
      end
    end

    it "filters references by query" do
      create(:mission, operation:, name: "Launch Plan")
      create(:mission, operation:, name: "Billing Cleanup")

      get references_admin_agent_alpha_path, params: { q: "billing" }

      mission_labels = response.parsed_body.fetch("groups")
                               .find { |group| group["kind"] == "missions" }
                               .fetch("items").pluck("label")
      expect(mission_labels).to contain_exactly("Billing Cleanup")
    end

    it "returns an empty reference list when Agent Alpha is not configured" do
      SystemPreference.where(tenant: user.tenant).delete_all

      get references_admin_agent_alpha_path, params: { q: "" }

      expect(response.parsed_body).to eq("groups" => [])
    end
  end

  def mission_reference_item(mission, mention:)
    hash_including(
      "id" => mission.id,
      "label" => mission.name,
      "mention" => mention,
      "display_tag" => "#mission_id:#{mission.id}",
    )
  end

  def client_reference_item(client)
    hash_including(
      "id" => client.id,
      "label" => client.name,
      "mention" => "#billing-portal",
      "display_tag" => "#client_id:#{client.id}",
    )
  end

  def create_client_reference(name:, operation:)
    create(:client, name:, agent: create(:agent, operation:, name: "#{name} Agent"))
  end

  def scoped_reference_groups
    fixtures = build_scoped_reference_fixtures

    get references_admin_agent_alpha_path, params: { q: "" }

    [response.parsed_body.fetch("groups").index_by { |group| group.fetch("kind") }, fixtures]
  end

  def build_scoped_reference_fixtures
    hidden_operation = create(:operation, tenant: user.tenant, name: "Hidden Workspace")
    catalog = create(:skill_catalog, operation:, name: "Writing Skills")
    other_tenant = create(:tenant).tap(&:ensure_core_resources!)

    {
      visible_mission: create(:mission, operation:, name: "Launch Plan"),
      hidden_mission_name: create(:mission, operation: hidden_operation, name: "Hidden Plan").name,
      visible_tool: create(:tool, :enabled, :rag_query, operation:, name: "Policy Search"),
      catalog:,
      visible_skill: create(:skill, skill_catalog: catalog, name: "Brief Writer"),
      visible_client: create_client_reference(name: "Billing Portal", operation:),
      hidden_client_name: create_client_reference(
        name: "Hidden Client",
        operation: other_tenant.default_operation,
      ).name,
    }
  end
end
