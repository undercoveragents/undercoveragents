# frozen_string_literal: true

module Admin
  # Admin interface for managing archival memories for a specific agent.
  #
  # Archival memories are per-user, per-agent semantic search entries. The
  # admin can filter by user, search semantically, and delete individual entries.
  # The agent is looked up through the tenant-scoped FriendlyId relation.
  #
  # Routes (namespace :admin):
  #   GET    /admin/agents/:agent_id/archival_memories
  #   POST   /admin/agents/:agent_id/archival_memories
  #   DELETE /admin/agents/:agent_id/archival_memories/:id
  #   POST   /admin/agents/:agent_id/archival_memories/search
  #
  class ArchivalMemoriesController < Admin::BaseController
    before_action :set_agent
    before_action :set_archival_memory, only: [:destroy]

    def index
      @users = users_with_memories
      @selected_user = selected_user
      @archival_memories = filtered_archival_memories
    end

    def create
      user = memory_user

      unless user
        redirect_to admin_agent_archival_memories_path(@agent), alert: t("archival_memories.no_user")
        return
      end

      service = build_embedding_service

      unless service
        redirect_to admin_agent_archival_memories_path(@agent), alert: t("archival_memories.no_connector")
        return
      end

      create_archival_memory!(user, service)
      redirect_to admin_agent_archival_memories_path(@agent, user_id: user.id), notice: t("archival_memories.created")
    rescue StandardError => e
      Rails.logger.error "[Admin::ArchivalMemoriesController#create] #{e.message}"
      redirect_to admin_agent_archival_memories_path(@agent), alert: "Failed to store memory: #{e.message}"
    end

    def destroy
      @archival_memory.destroy!
      redirect_to admin_agent_archival_memories_path(@agent), notice: t("archival_memories.destroyed")
    end

    def search
      service = build_embedding_service

      unless service
        redirect_to admin_agent_archival_memories_path(@agent), alert: t("archival_memories.no_connector")
        return
      end

      @users          = users_with_memories
      @query          = params[:query]
      @selected_user  = selected_user
      @tags           = search_tags

      @results = ArchivalMemory.semantic_search(**memory_search_params(service))
    end

    private

    def set_agent
      @agent = scoped_agents.friendly.find(params.expect(:agent_id))
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_memory_blocks_path, alert: t("shared.not_found")
    end

    def set_archival_memory
      @archival_memory = @agent.archival_memories.find(params.expect(:id))
    end

    def archival_memory_params
      params.expect(archival_memory: [:content, :tags, :user_id])
    end

    def memory_user
      current_tenant.users.find_by(id: archival_memory_params[:user_id])
    end

    def create_archival_memory!(user, service)
      content = archival_memory_params[:content]
      embedding = service.embed(content)

      ArchivalMemory.create!(
        agent: @agent,
        user:,
        content:,
        embedding:,
        tags: parse_tags(archival_memory_params[:tags]),
      )
    end

    def parse_tags(tags_string)
      tags_string.to_s.split(",").map(&:strip).compact_blank
    end

    def filtered_archival_memories
      scope = @agent.archival_memories.recent
      scope = scope.for_user(@selected_user.id) if @selected_user
      return scope if params[:tags].blank?

      scope.with_tags(params.expect(:tags).split(",").map(&:strip))
    end

    def selected_user
      current_tenant.users.find_by(id: params[:user_id])
    end

    def search_tags
      params[:tags].present? ? params.expect(:tags).split(",").map(&:strip) : []
    end

    def memory_search_params(service)
      search_params = { agent_id: @agent.id, query_embedding: service.embed(@query), tags: @tags, page: search_page }
      search_params[:user_id] = @selected_user.id if @selected_user
      search_params
    end

    def search_page
      (params[:page] || 0).to_i
    end

    def users_with_memories
      current_tenant.users.where(id: @agent.archival_memories.select(:user_id)).distinct
    end

    def build_embedding_service
      memory_config = @agent.capability("memory")
      return nil unless memory_config.respond_to?(:embedding_connector)

      connector = memory_config.embedding_connector
      return nil unless connector

      Capabilities::Memory::EmbeddingService.new(connector:, model: memory_config.model_id)
    end
  end
end
