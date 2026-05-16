# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordComplexityValidator do
  subject(:model) { validatable_class.new(password:) }

  let(:validatable_class) do
    Class.new do
      include ActiveModel::Validations

      attr_accessor :password

      validates :password, password_complexity: true

      def initialize(password:)
        @password = password
      end
    end
  end

  context "with a fully compliant password" do
    let(:password) { "Secure1!" }

    it { is_expected.to be_valid }
  end

  context "with a blank password" do
    let(:password) { "" }

    it "skips validation (blank handled elsewhere)" do
      expect(model).to be_valid
    end
  end

  context "without uppercase" do
    let(:password) { "lowercase1!" }

    it "is invalid" do
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include("must include at least one uppercase letter")
    end
  end

  context "without lowercase" do
    let(:password) { "UPPERCASE1!" }

    it "is invalid" do
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include("must include at least one lowercase letter")
    end
  end

  context "without digit" do
    let(:password) { "NoDigits!!" }

    it "is invalid" do
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include("must include at least one digit")
    end
  end

  context "without special character" do
    let(:password) { "NoSpecial1" }

    it "is invalid" do
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include("must include at least one special character")
    end
  end

  context "with only digits and special" do
    let(:password) { "12345678!" }

    it "is invalid with multiple errors" do
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include("must include at least one uppercase letter")
      expect(model.errors[:password]).to include("must include at least one lowercase letter")
    end
  end
end
