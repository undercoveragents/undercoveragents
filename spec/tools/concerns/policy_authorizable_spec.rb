# frozen_string_literal: true

require "rails_helper"

RSpec.describe PolicyAuthorizable do
  subject(:authorizer) do
    Class.new do
      include PolicyAuthorizable

      public :authorize_policy!
    end.new
  end

  describe "#authorize_policy!" do
    it "raises when a policy class is missing" do
      expect do
        authorizer.authorize_policy!(Object.new, :show?, user: nil)
      end.to raise_error(ArgumentError, "Missing policy for Object.")
    end
  end
end
