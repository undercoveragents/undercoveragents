# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    before_action :require_api_authentication

    private

    attr_reader :current_api_client

    def require_api_authentication
      token = extract_bearer_token
      @current_api_client = ApiClient.authenticate(token)

      render_unauthorized unless @current_api_client
    end

    def extract_bearer_token
      header = request.headers["Authorization"]
      return nil unless header&.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip
    end

    def render_unauthorized
      render json: { error: "Unauthorized", message: "Invalid or missing API token" }, status: :unauthorized
    end

    def render_forbidden(message = "Access denied")
      render json: { error: "Forbidden", message: }, status: :forbidden
    end

    def render_not_found(message = "Resource not found")
      render json: { error: "Not Found", message: }, status: :not_found
    end

    def render_unprocessable(message)
      render json: { error: "Unprocessable Entity", message: }, status: :unprocessable_content
    end
  end
end
