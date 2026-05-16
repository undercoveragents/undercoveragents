# frozen_string_literal: true

module Admin
  # Admin interface for managing global Memory Blocks.
  #
  # Memory blocks are shared objects used by agents for core (always-in-context)
  # memory. Because a single block can be shared across agents and pipeline
  # versions, editing is centralised here and restricted to admins.
  #
  # Routes (namespace :admin):
  #   GET    /admin/memory_blocks
  #   GET    /admin/memory_blocks/:label
  #   GET    /admin/memory_blocks/new
  #   POST   /admin/memory_blocks
  #   PATCH  /admin/memory_blocks/:label
  #   DELETE /admin/memory_blocks/:label
  #
  class MemoryBlocksController < Admin::BaseController
    helper MemoryBlocksHelper

    before_action :set_memory_block, only: [:show, :update, :destroy]

    def index
      @memory_blocks = MemoryBlock.ordered
    end

    def show
      @my_blocks = AgentMemoryBlock.where(memory_block: @memory_block, user: current_user)
                                   .eager_load(:agent)
                                   .order("agents.name")
    end

    def new
      @memory_block = MemoryBlock.new
    end

    def create
      @memory_block = MemoryBlock.new(memory_block_create_params)

      if @memory_block.save
        redirect_to admin_memory_blocks_path, notice: t("memory_blocks.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      return redirect_read_only if @memory_block.read_only?

      if @memory_block.update(memory_block_update_params)
        redirect_to admin_memory_block_path(@memory_block.label), notice: t("memory_blocks.updated")
      else
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      @memory_block.destroy!
      redirect_to admin_memory_blocks_path, notice: t("memory_blocks.destroyed")
    end

    private

    def set_memory_block
      @memory_block = MemoryBlock.find_by!(label: params.expect(:label))
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_memory_blocks_path, alert: t("memory_blocks.not_found")
    end

    def memory_block_create_params
      params.expect(memory_block: [:label, :description, :default_value, :char_limit, :read_only])
    end

    def memory_block_update_params
      params.expect(memory_block: [:default_value, :description, :char_limit])
    end

    def redirect_read_only
      redirect_to admin_memory_block_path(@memory_block.label), alert: t("memory_blocks.read_only")
    end
  end
end
