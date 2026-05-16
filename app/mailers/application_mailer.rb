# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: lambda {
    ENV["MAILER_FROM_EMAIL"].presence ||
      ENV["RESEND_FROM_EMAIL"].presence ||
      "no-reply@example.invalid"
  }
  layout "mailer"
end
