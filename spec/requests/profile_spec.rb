# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile", :unauthenticated do
  let(:user) { create(:user) }

  before { sign_in(user) }

  describe "GET /profile" do
    it "returns a successful response" do
      get profile_path
      expect(response).to have_http_status(:ok)
    end
  end
end
