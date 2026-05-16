# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserMailer do
  describe "#password_reset" do
    let(:user) { create(:user, email: "user@example.com") }
    let(:token) { user.password_reset_token }

    around do |example|
      original_mailer_from_email = ENV.fetch("MAILER_FROM_EMAIL", nil)
      original_resend_from_email = ENV.fetch("RESEND_FROM_EMAIL", nil)
      ENV.delete("MAILER_FROM_EMAIL")
      ENV.delete("RESEND_FROM_EMAIL")

      example.run
    ensure
      ENV["MAILER_FROM_EMAIL"] = original_mailer_from_email
      ENV["RESEND_FROM_EMAIL"] = original_resend_from_email
    end

    it "sends to the user email" do
      mail = described_class.password_reset(user, token)
      expect(mail.to).to eq(["user@example.com"])
    end

    it "uses the configured sender address" do
      ENV["MAILER_FROM_EMAIL"] = "security@example.com"

      mail = described_class.password_reset(user, token)

      expect(mail.from).to eq(["security@example.com"])
    end

    it "falls back to the Resend sender address" do
      ENV["RESEND_FROM_EMAIL"] = "security@example.com"

      mail = described_class.password_reset(user, token)

      expect(mail.from).to eq(["security@example.com"])
    end

    it "sets the correct subject" do
      mail = described_class.password_reset(user, token)
      expect(mail.subject).to eq("Reset your password — Undercover Agents")
    end

    it "includes the reset link in the body" do
      mail = described_class.password_reset(user, token)
      expect(mail.body.encoded).to include("password_resets/")
      expect(mail.body.encoded).to include("/edit")
    end

    it "includes the user display name" do
      mail = described_class.password_reset(user, token)
      expect(mail.body.encoded).to include(user.display_name)
    end

    it "includes expiry information" do
      mail = described_class.password_reset(user, token)
      expect(mail.body.encoded).to include("2 hours")
    end
  end
end
