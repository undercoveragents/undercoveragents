# frozen_string_literal: true

module Channels
  class Api
    include UndercoverAgents::PluginSystem::Configurator
    include ChannelPlugin

    ACCESS_SCOPES = ["all", "scoped"].freeze
    RESPONSE_MODES = ["async", "sync"].freeze

    attribute :access_scope, :string, default: "all"
    attribute :response_mode, :string, default: "async"
    attribute :callback_url, :string

    validates :access_scope, inclusion: { in: ACCESS_SCOPES }
    validates :response_mode, inclusion: { in: RESPONSE_MODES }
    validates :callback_url, length: { maximum: 2000 }, allow_blank: true

    key "api"
    label "API"
    icon "fa-solid fa-code"
    description "Expose assigned agents or missions through token-authenticated API endpoints."
    target_kinds ["agent", "mission"]

    def self.permitted_params(params)
      params.fetch(:channel, ActionController::Parameters.new).permit(:access_scope, :response_mode, :callback_url)
    end

    def summary
      [scope_all? ? "All tenant missions" : "Scoped missions", response_mode == "sync" ? "Sync" : "Async"].join(" / ")
    end

    def form_partial_path
      Rails.root.join("app/views/channels/api")
    end

    def show_partial_path
      form_partial_path
    end

    def scope_all?
      access_scope == "all"
    end

    def scope_scoped?
      access_scope == "scoped"
    end
  end
end
