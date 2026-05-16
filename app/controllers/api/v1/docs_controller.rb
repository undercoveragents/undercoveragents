# frozen_string_literal: true

module Api
  module V1
    class DocsController < ActionController::API
      def show
        render json: Api::SwaggerDocGenerator.new.call
      end
    end
  end
end
