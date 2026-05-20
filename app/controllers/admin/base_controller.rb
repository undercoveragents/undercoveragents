# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    ADMIN_REFERER_PATTERN = %r{\A(?:https?://[^/]+)?/admin(?:[/?]|\z)}
    DUPLICATE_NAME_PREFIX = "Copy of "

    layout "admin"

    prepend_view_path Rails.root.join("app/views/admin")

    before_action :require_admin
    before_action :reset_operation_to_default_on_admin_entry

    private

    def require_admin
      return if current_user.admin?

      redirect_to root_path, alert: t("auth.admin_required")
    end

    def reset_operation_to_default_on_admin_entry
      return unless request.get? && request.path == admin_root_path && params[:operation].blank?
      return if request.referer.to_s.match?(ADMIN_REFERER_PATTERN)

      Operation.set_current_operation(session, current_tenant&.default_operation)
    end

    def duplicate_name_for(scope, source_name)
      base_name = "#{DUPLICATE_NAME_PREFIX}#{source_name}"
      candidate = base_name
      suffix = 2

      while scope.exists?(["LOWER(name) = ?", candidate.downcase])
        candidate = "#{base_name} (#{suffix})"
        suffix += 1
      end

      candidate
    end
  end
end
