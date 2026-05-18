# frozen_string_literal: true

module Telegram
  module Admin
    class ChannelsController < ::Admin::BaseController
      before_action :set_channel

      def setup_webhook
        authorize @channel

        result = Telegram::WebhookSetupService.new(@channel, host: request.host_with_port).call
        flash[result.success? ? :notice : :alert] = result.message
        redirect_to admin_channel_path(@channel), status: :see_other
      end

      private

      def set_channel
        @channel = scoped_channels.by_type(Channels::Telegram.key).friendly.find(params.expect(:id))
      end
    end
  end
end
