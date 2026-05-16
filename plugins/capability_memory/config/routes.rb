# frozen_string_literal: true

namespace :admin do
  resources :memory_blocks, param: :label, except: [:edit]

  resources :agents, only: [] do
    resources :archival_memories, only: [:index, :create, :destroy] do
      collection do
        post :search
      end
    end
  end
end
