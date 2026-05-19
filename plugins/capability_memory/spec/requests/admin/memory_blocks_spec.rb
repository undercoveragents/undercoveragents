# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::MemoryBlocks" do
  let!(:memory_block) do
    create(
      :memory_block,
      label: "persona",
      description: "Persona details",
      default_value: "Helpful assistant",
      char_limit: 100,
    )
  end

  describe "GET /admin/memory_blocks" do
    it "renders the memory block index" do
      get admin_memory_blocks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(memory_block.label)
    end
  end

  describe "GET /admin/memory_blocks/:label" do
    it "renders the selected memory block" do
      get admin_memory_block_path(memory_block.label)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(memory_block.label)
    end

    it "redirects when the memory block is missing" do
      get admin_memory_block_path("missing_block")

      expect(response).to redirect_to(admin_memory_blocks_path)
      expect(flash[:alert]).to eq(I18n.t("memory_blocks.not_found"))
    end
  end

  describe "GET /admin/memory_blocks/new" do
    it "renders the new memory block form" do
      get new_admin_memory_block_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/memory_blocks" do
    it "creates a memory block with valid params" do
      expect do
        post admin_memory_blocks_path, params: {
          memory_block: {
            label: "workspace_notes",
            description: "Workspace-scoped notes",
            default_value: "",
            char_limit: 250,
            read_only: false,
          },
        }
      end.to change(MemoryBlock, :count).by(1)

      created_block = MemoryBlock.order(:id).last
      expect(response).to redirect_to(admin_memory_blocks_path)
      expect(created_block).to have_attributes(
        label: "workspace_notes",
        description: "Workspace-scoped notes",
        default_value: "",
        char_limit: 250,
        read_only: false,
      )
    end

    it "renders the form again when params are invalid" do
      expect do
        post admin_memory_blocks_path, params: {
          memory_block: {
            label: "Bad Label",
            description: "Invalid label",
            default_value: "",
            char_limit: 250,
            read_only: false,
          },
        }
      end.not_to change(MemoryBlock, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/memory_blocks/:label" do
    it "redirects when the block is read only" do
      read_only_block = create(
        :memory_block,
        :read_only,
        label: "read_only_block",
        default_value: "Fixed",
        char_limit: 100,
      )

      patch admin_memory_block_path(read_only_block.label), params: {
        memory_block: {
          default_value: "Changed",
          description: "Updated",
          char_limit: 99,
        },
      }

      expect(response).to redirect_to(admin_memory_block_path(read_only_block.label))
      expect(flash[:alert]).to eq(I18n.t("memory_blocks.read_only"))
      expect(read_only_block.reload.default_value).to eq("Fixed")
    end

    it "updates writable blocks with valid params" do
      patch admin_memory_block_path(memory_block.label), params: {
        memory_block: {
          default_value: "Updated persona",
          description: "Updated details",
          char_limit: 120,
        },
      }

      expect(response).to redirect_to(admin_memory_block_path(memory_block.label))
      expect(memory_block.reload).to have_attributes(
        default_value: "Updated persona",
        description: "Updated details",
        char_limit: 120,
      )
    end

    it "renders the show template again when the update is invalid" do
      patch admin_memory_block_path(memory_block.label), params: {
        memory_block: {
          default_value: "x" * 101,
          description: "Too long",
          char_limit: 100,
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(memory_block.reload.default_value).to eq("Helpful assistant")
    end
  end

  describe "DELETE /admin/memory_blocks/:label" do
    it "destroys the selected memory block" do
      deletable_block = create(:memory_block, label: "temporary_block")

      expect do
        delete admin_memory_block_path(deletable_block.label)
      end.to change(MemoryBlock, :count).by(-1)

      expect(response).to redirect_to(admin_memory_blocks_path)
    end
  end
end
