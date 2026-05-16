# frozen_string_literal: true

class ModelRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Model.refresh!
  end
end
