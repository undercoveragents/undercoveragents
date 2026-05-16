# frozen_string_literal: true

class DownloadsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:show]

  def show
    blob = ActiveStorage::Blob.find_signed!(params[:id])
    send_data blob.download, filename: blob.filename.to_s, type: blob.content_type, disposition: "attachment"
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    head :not_found
  end
end
