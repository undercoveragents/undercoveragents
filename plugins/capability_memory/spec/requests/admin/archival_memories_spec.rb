# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ArchivalMemories" do
  let(:agent_llm_connector) { create(:connector, :llm_provider, :enabled, tenant: default_tenant) }
  let(:agent) { create(:agent, operation: default_operation, llm_connector: agent_llm_connector) }
  let(:own_user) { create(:user, tenant: default_tenant, email: "tenant-user@example.com") }

  def enable_memory(agent, connector:)
    agent.set_capability_config(
      "memory",
      {
        "llm_connector_id" => connector.id,
        "model_id" => "text-embedding-3-small",
        "auto_bootstrap" => false,
      },
      enabled: true,
    )
    agent.save!
  end

  def stub_embedding_service(result: Array.new(1536, 0.1))
    service = instance_double(Capabilities::Memory::EmbeddingService, embed: result)
    allow(Capabilities::Memory::EmbeddingService).to receive(:new).and_return(service)
    service
  end

  def stub_search_results(results)
    allow(ArchivalMemory).to receive(:semantic_search).and_return(results)
  end

  describe "GET /admin/agents/:agent_id/archival_memories" do
    it "only lists users from the current tenant" do
      foreign_user = create(:user, tenant: create(:tenant), email: "foreign-user@example.com")
      create(:archival_memory, agent:, user: own_user, content: "Remember this")

      get admin_agent_archival_memories_path(agent)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(own_user.email)
      expect(response.body).not_to include(foreign_user.email)
    end

    it "filters memories by selected user and tags" do
      other_user = create(:user, tenant: default_tenant, email: "other-user@example.com")
      create(:archival_memory, agent:, user: own_user, content: "Rails memory", tags: ["rails"])
      create(:archival_memory, agent:, user: own_user, content: "Ops memory", tags: ["ops"])
      create(:archival_memory, agent:, user: other_user, content: "Foreign to filter", tags: ["rails"])

      get admin_agent_archival_memories_path(agent), params: { user_id: own_user.id, tags: "rails" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rails memory")
      expect(response.body).not_to include("Ops memory")
      expect(response.body).not_to include("Foreign to filter")
    end

    it "redirects when the agent is outside the current tenant scope" do
      get admin_agent_archival_memories_path("missing-agent")

      expect(response).to redirect_to(admin_memory_blocks_path)
    end
  end

  describe "POST /admin/agents/:agent_id/archival_memories" do
    it "rejects users from other tenants" do
      foreign_user = create(:user, tenant: create(:tenant), email: "foreign-user@example.com")

      expect do
        post admin_agent_archival_memories_path(agent), params: {
          archival_memory: {
            user_id: foreign_user.id,
            content: "Do not store",
            tags: "",
          },
        }
      end.not_to change(ArchivalMemory, :count)

      expect(response).to redirect_to(admin_agent_archival_memories_path(agent))
    end

    it "redirects when the memory capability configurator is unavailable" do
      allow(CapabilityPlugin).to receive(:resolve).and_call_original
      allow(CapabilityPlugin).to receive(:resolve).with("memory").and_return(nil)

      post admin_agent_archival_memories_path(agent), params: {
        archival_memory: {
          user_id: own_user.id,
          content: "No capability",
          tags: "",
        },
      }

      expect(response).to redirect_to(admin_agent_archival_memories_path(agent))
    end

    it "redirects when no embedding connector is configured" do
      post admin_agent_archival_memories_path(agent), params: {
        archival_memory: {
          user_id: own_user.id,
          content: "No connector",
          tags: "",
        },
      }

      expect(response).to redirect_to(admin_agent_archival_memories_path(agent))
    end

    it "stores memory when the embedding service succeeds" do
      enable_memory(agent, connector: agent_llm_connector)
      stub_embedding_service

      expect do
        post admin_agent_archival_memories_path(agent), params: {
          archival_memory: {
            user_id: own_user.id,
            content: "Store this",
            tags: "rails, prefs",
          },
        }
      end.to change(ArchivalMemory, :count).by(1)

      expect(response).to redirect_to(admin_agent_archival_memories_path(agent, user_id: own_user.id))
      memory = ArchivalMemory.order(:id).last
      expect(memory.content).to eq("Store this")
      expect(memory.tags).to eq(["rails", "prefs"])
    end

    it "redirects with an error when embedding fails" do
      enable_memory(agent, connector: agent_llm_connector)
      service = instance_double(Capabilities::Memory::EmbeddingService)
      allow(service).to receive(:embed).and_raise(StandardError, "boom")
      allow(Capabilities::Memory::EmbeddingService).to receive(:new).and_return(service)
      allow(Rails.logger).to receive(:error)

      expect do
        post admin_agent_archival_memories_path(agent), params: {
          archival_memory: {
            user_id: own_user.id,
            content: "Explode",
            tags: "ops",
          },
        }
      end.not_to change(ArchivalMemory, :count)

      expect(response).to redirect_to(admin_agent_archival_memories_path(agent))
      expect(flash[:alert]).to include("Failed to store memory: boom")
    end
  end

  describe "DELETE /admin/agents/:agent_id/archival_memories/:id" do
    it "destroys the memory entry" do
      memory = create(:archival_memory, agent:, user: own_user, content: "Delete me")

      expect do
        delete admin_agent_archival_memory_path(agent, memory)
      end.to change(ArchivalMemory, :count).by(-1)

      expect(response).to redirect_to(admin_agent_archival_memories_path(agent))
    end
  end

  describe "POST /admin/agents/:agent_id/archival_memories/search" do
    it "redirects when no embedding connector is configured" do
      post search_admin_agent_archival_memories_path(agent), params: { query: "rails" }

      expect(response).to redirect_to(admin_agent_archival_memories_path(agent))
    end

    it "renders results for a filtered search" do
      enable_memory(agent, connector: agent_llm_connector)
      stub_embedding_service(result: Array.new(1536, 0.2))
      stub_search_results([
                            { id: 123, content: "Matched memory", score: 0.98, tags: ["rails", "prefs"] },
                          ])

      post search_admin_agent_archival_memories_path(agent), params: {
        query: "rails",
        tags: "rails, prefs",
        page: 2,
        user_id: own_user.id,
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Matched memory")
    end

    it "passes user, tag, and page filters to semantic search" do
      enable_memory(agent, connector: agent_llm_connector)
      stub_embedding_service(result: Array.new(1536, 0.2))
      stub_search_results([
                            { id: 123, content: "Matched memory", score: 0.98, tags: ["rails", "prefs"] },
                          ])

      post search_admin_agent_archival_memories_path(agent), params: {
        query: "rails",
        tags: "rails, prefs",
        page: 2,
        user_id: own_user.id,
      }

      expect(ArchivalMemory).to have_received(:semantic_search) do |**kwargs|
        expect(kwargs[:agent_id]).to eq(agent.id)
        expect(kwargs[:user_id]).to eq(own_user.id)
        expect(kwargs[:tags]).to eq(["rails", "prefs"])
        expect(kwargs[:page]).to eq(2)
      end
    end

    it "renders results when page and user filters are omitted" do
      enable_memory(agent, connector: agent_llm_connector)
      stub_embedding_service(result: Array.new(1536, 0.3))
      stub_search_results([
                            { id: 456, content: "Default search", score: 0.75, tags: [] },
                          ])

      post search_admin_agent_archival_memories_path(agent), params: { query: "default" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Default search")
    end

    it "defaults to page zero and no user filter when omitted" do
      enable_memory(agent, connector: agent_llm_connector)
      stub_embedding_service(result: Array.new(1536, 0.3))
      stub_search_results([
                            { id: 456, content: "Default search", score: 0.75, tags: [] },
                          ])

      post search_admin_agent_archival_memories_path(agent), params: { query: "default" }

      expect(ArchivalMemory).to have_received(:semantic_search) do |**kwargs|
        expect(kwargs[:agent_id]).to eq(agent.id)
        expect(kwargs[:tags]).to eq([])
        expect(kwargs[:page]).to eq(0)
        expect(kwargs).not_to have_key(:user_id)
      end
    end
  end
end
