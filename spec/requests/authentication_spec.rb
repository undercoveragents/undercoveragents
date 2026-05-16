# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication", :unauthenticated do
  describe "XHR request to protected route" do
    it "redirects without setting return_to in session (XHR skips return_to)" do
      get root_path, headers: { "X-Requested-With" => "XMLHttpRequest" }

      expect(response).to redirect_to(new_session_path)
      expect(session[:return_to]).to be_nil
    end

    it "sets return_to in session for regular (non-XHR) requests" do
      get root_path

      expect(response).to redirect_to(new_session_path)
      expect(session[:return_to]).to eq(root_path)
    end
  end
end
