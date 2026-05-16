# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ChatProfile" do
  describe "GET /chat/profile" do
    it "returns a successful response" do
      get chat_profile_path
      expect(response).to have_http_status(:ok)
    end

    context "when unauthenticated", :unauthenticated do
      it "redirects to login" do
        get chat_profile_path
        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
