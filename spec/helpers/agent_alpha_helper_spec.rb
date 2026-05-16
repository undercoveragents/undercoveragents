# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentAlphaHelper do
  describe "#agent_alpha_page_context_token" do
    it "returns nil outside admin requests" do
      user = create(:user, :admin)
      request = instance_double(ActionDispatch::Request, path: "/login")

      helper.define_singleton_method(:current_user) { user }
      helper.define_singleton_method(:request) { request }

      expect(helper.agent_alpha_page_context_token).to be_nil
    end
  end
end
