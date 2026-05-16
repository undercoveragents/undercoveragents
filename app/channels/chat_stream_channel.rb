# frozen_string_literal: true

class ChatStreamChannel < ApplicationCable::Channel
  def subscribed
    return reject if stream_name.blank?

    stream_from stream_name
  end

  def unsubscribed
    stop_all_streams
  end

  private

  def stream_name
    @stream_name ||= Chat.verified_stream_name(params[:stream_token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
