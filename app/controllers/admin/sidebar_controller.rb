# frozen_string_literal: true

module Admin
  class SidebarController < BaseController
    def update
      session[:sidebar_collapsed] = ActiveModel::Type::Boolean.new.cast(params[:collapsed])
      head :no_content
    end
  end
end
