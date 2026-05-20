# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Short file download URL (filename segment is cosmetic, for link display)
  get "dl/:id(/*filename)", to: "downloads#show", as: :short_download

  # ── Authentication ──
  get "login", to: "sessions#new", as: :new_session
  post "login", to: "sessions#create", as: :sessions
  get "tenants/:tenant_id/login", to: "sessions#new", as: :tenant_login
  post "tenants/:tenant_id/login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :session
  get "try-in-cloud", to: "cloud_signups#new", as: :new_cloud_signup
  post "try-in-cloud", to: "cloud_signups#create", as: :cloud_signup

  # Password reset (forgot password)
  resources :password_resets, only: [:new, :create, :edit, :update], param: :token

  # Password change (authenticated)
  resource :password_change, only: [:edit, :update]

  # Profile (user settings)
  resource :profile, only: [:show], controller: "profile"

  # OmniAuth callbacks
  get "auth/:provider/callback", to: "omniauth_callbacks#create"
  get "auth/failure", to: "omniauth_callbacks#failure"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Load plugin routes BEFORE admin namespace so specific plugin routes take
  # priority over generic resource routes (e.g., /admin/connectors/:id)
  if defined?(UndercoverAgents::PluginSystem)
    UndercoverAgents::PluginSystem.registry.all.to_a.each do |plugin|
      routes_path = plugin.root_path&.join("config/routes.rb")
      next unless routes_path&.exist?

      instance_eval(routes_path.read, routes_path.to_s)
    end
  end

  # ── Chat (end-user interface) ──
  resource :chat_profile, only: [:show], path: "chat/profile", controller: "chat_profile"
  resources :chats, path: "chat", only: [:index, :show, :create, :destroy] do
    resource :messages, only: [:create]
    member do
      post :cancel
      post "messages/:message_id/feedback", to: "messages#feedback", as: :message_feedback
    end
    collection do
      get :more
    end
  end

  # ── API ──
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      get "swagger", to: "docs#show", as: :swagger, defaults: { format: :json }
      post "automation_webhooks/:id", to: "automation_webhooks#create", as: :automation_webhook
      post "mission_webhooks/:id", to: "automation_webhooks#create", as: :mission_webhook

      post "channels/:channel_slug/targets/:target_slug/invocations",
           to: "channel_invocations#create",
           as: :channel_target_invocations
      get "channels/:channel_slug/targets/:target_slug/invocations/:id",
          to: "channel_invocations#show",
          as: :channel_target_invocation
    end
  end

  # ── Admin ──
  namespace :admin do
    concern :automatable do
      resources :automation_triggers, path: "automation", except: [:show] do
        member do
          post :regenerate_secret
        end
      end
    end

    # Dashboard
    root "dashboard#show"

    # Sidebar state persistence
    resource :sidebar, only: [:update], controller: "sidebar"

    # Persistent Agent Alpha panel
    resource :agent_alpha, only: [:show], controller: "agent_alphas" do
      resource :messages, only: [:create], controller: "agent_alpha_messages"
      post "messages/:message_id/feedback", to: "agent_alpha_messages#feedback", as: :message_feedback
      get :references, to: "agent_alpha_references#index"
      member { post :cancel }
    end

    # Users & Plugins & Operations
    resources :tenants, except: [:show]
    resources :users, except: [:show]
    resources :plugins, only: [:index] do
      member do
        patch :toggle
      end
    end
    resources :operations, except: [:show] do
      member do
        post :switch
      end
    end

    # System Preferences
    resource :preferences, only: [:show, :update]

    # Build section — missions, agents, tools, rag_flows, test_suites
    resources :missions do
      member do
        post :clone, action: :clone_record
        get :designer
        patch :save_flow, to: "mission_flows#save_flow"
        get :flow_data_json, to: "mission_flows#flow_data_json"
        get :debug_inputs, to: "mission_debug_runs#debug_inputs"
        post :execute_debug, to: "mission_debug_runs#execute_debug"
        get :run_status, to: "mission_debug_runs#run_status"
        get :run_catch_up, to: "mission_debug_runs#run_catch_up"
        post :cancel_run, to: "mission_debug_runs#cancel_run"
        get :load_debug_run, to: "mission_debug_runs#load_debug_run"
        post :reset_debug, to: "mission_debug_runs#reset_debug"
        get :node_model_options, to: "mission_flows#node_model_options"
        get :node_image_model_options, to: "mission_flows#node_image_model_options"
        get :mission_io_fields, to: "mission_flows#mission_io_fields"
        post :duplicate_node, to: "mission_flows#duplicate_node"
        post :delete_node, to: "mission_flows#delete_node"
        post :undo_flow, to: "mission_flows#undo_flow"
        post :redo_flow, to: "mission_flows#redo_flow"
        get :node_properties, to: "mission_flows#node_properties"
      end

      concerns :automatable
      resources :mission_triggers, path: "automation", controller: "automation_triggers", except: [:show] do
        member do
          post :regenerate_secret
        end
      end
    end

    resources :agents do
      collection do
        get :embedding_model_options
        get :image_model_options
        get :model_options
        post :restore_defaults
      end
      member do
        post :clone, action: :clone_record
        get :edit_instructions
        patch :toggle
        post :restore
        post :add_tool
        delete :remove_tool
        post :add_capability
        post :add_subagent
        delete :remove_subagent
        post :add_skill_catalog
        delete :remove_skill_catalog
      end
      resources :capabilities, only: [:edit, :update, :destroy], param: :key
    end

    resources :skill_catalogs do
      collection do
        get :import
        post :import, action: :create_import
        post :restore_defaults
      end
      member do
        post :restore
        post :attach_agent
        delete :detach_agent
      end
      resources :skills do
        collection do
          get :import
          post :import, action: :create_import
        end
        member do
          post :restore
        end
      end
    end

    resources :models, only: [:index] do
      collection do
        post :refresh
      end
    end

    resources :tools do
      member do
        post :clone, action: :clone_record
        get :edit_instructions
        get :edit_widget
        patch :update_widget
        patch :toggle
        post :discover_schema
        get :edit_visibility
        patch :update_visibility
      end
    end

    # RAG
    resources :rag_flows do
      member do
        patch :toggle
        post :execute
      end
      concerns :automatable
      resources :steps, controller: "rag/steps", only: [:edit, :update, :destroy], param: :stage
      resources :runs, controller: "rag/runs", only: [:index, :show] do
        member do
          post :cancel
        end
      end
    end

    # Test Suites
    resources :test_suites do
      member do
        post :run_suite
      end
      resources :test_cases, only: [:create, :update, :destroy]
      resources :test_suite_runs, only: [:show] do
        member do
          post :cancel
        end
      end
    end

    # Channels
    resources :channels do
      member do
        patch :toggle
        post :regenerate_token
      end
    end

    # Connectors (global, not versioned)
    get "connectors/provider_fields", to: "connectors#provider_fields", as: :provider_fields_connectors
    resources :connectors do
      member do
        patch :toggle
      end
    end

    # Playground
    namespace :playground do
      resources :chats, only: [:index, :show, :create, :destroy] do
        resource :messages, only: [:create]
        member do
          post :cancel
          post "messages/:message_id/retry", to: "messages#retry", as: :message_retry
          post "messages/:message_id/feedback", to: "messages#feedback", as: :message_feedback
        end
        collection do
          get :more
        end
      end
    end

    # Inspector — Chat debug UI
    namespace :inspector do
      resources :chats, only: [:index, :show]
    end

    # Mission Control — Mission runs monitoring
    namespace :mission_control do
      resources :runs, only: [:index, :show] do
        member { get :timeline }
      end
    end

    # Mission Control — Jobs dashboard
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  # Defines the root path route ("/")
  root "chats#index"
end
