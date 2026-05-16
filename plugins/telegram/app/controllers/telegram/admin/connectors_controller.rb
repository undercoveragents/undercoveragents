# frozen_string_literal: true

module Telegram
  module Admin
    class ConnectorsController < ::Admin::BaseController
      before_action :set_connector

      def fetch_bot_info
        authorize @connector

        return redirect_not_telegram unless @connector.connector_type == "telegram"

        @connector.fetch_bot_info!
        @connector.save!

        redirect_to admin_connector_path(@connector),
                    notice: t("connectors.telegram.bot_info_fetched", username: @connector.bot_username),
                    status: :see_other
      rescue StandardError => e
        redirect_to admin_connector_path(@connector),
                    alert: t("connectors.telegram.bot_info_failed", error: e.message),
                    status: :see_other
      end

      private

      def set_connector
        @connector = current_tenant.connectors.friendly.find(params.expect(:id))
      end

      def redirect_not_telegram
        redirect_to admin_connector_path(@connector),
                    alert: t("connectors.telegram.not_telegram"),
                    status: :see_other
      end
    end
  end
end
