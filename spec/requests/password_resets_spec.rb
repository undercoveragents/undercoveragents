# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PasswordResets", :unauthenticated do
  describe "GET /password_resets/new" do
    it "renders the forgot password page" do
      get new_password_reset_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects to root when already signed in" do
      user = create(:user)
      post sessions_path, params: { email: user.email, password: "Password123!" }

      get new_password_reset_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /password_resets" do
    let(:user) { create(:user, email: "reset@test.com") }

    before { user }

    it "sends a password reset email for existing account" do
      expect do
        post password_resets_path, params: { email: "reset@test.com" }
      end.to have_enqueued_mail(UserMailer, :password_reset)
    end

    it "redirects with notice regardless of email existence" do
      post password_resets_path, params: { email: "reset@test.com" }
      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("password reset link has been sent")
    end

    it "does not send email for nonexistent account" do
      expect do
        post password_resets_path, params: { email: "nonexistent@test.com" }
      end.not_to have_enqueued_mail(UserMailer, :password_reset)
    end

    it "shows same message for nonexistent account (no enumeration)" do
      post password_resets_path, params: { email: "nonexistent@test.com" }
      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("password reset link has been sent")
    end

    it "does not send email for OAuth accounts" do
      create(:user, :oauth, email: "oauth@test.com")
      expect do
        post password_resets_path, params: { email: "oauth@test.com" }
      end.not_to have_enqueued_mail(UserMailer, :password_reset)
    end

    it "does not send email for inactive accounts" do
      create(:user, :inactive, email: "inactive@test.com")
      expect do
        post password_resets_path, params: { email: "inactive@test.com" }
      end.not_to have_enqueued_mail(UserMailer, :password_reset)
    end

    it "handles missing email param gracefully (nil email)" do
      expect do
        post password_resets_path, params: {}
      end.not_to have_enqueued_mail(UserMailer, :password_reset)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /password_resets/:token/edit" do
    let(:user) { create(:user) }

    it "renders the reset password form for valid token" do
      token = user.password_reset_token
      get edit_password_reset_path(token:)
      expect(response).to have_http_status(:ok)
    end

    it "redirects for invalid token" do
      get edit_password_reset_path(token: "invalid")
      expect(response).to redirect_to(new_password_reset_path)
    end

    it "redirects for expired token" do
      token = user.password_reset_token
      Timecop.travel(3.hours.from_now) do
        get edit_password_reset_path(token:)
        expect(response).to redirect_to(new_password_reset_path)
      end
    end
  end

  describe "PATCH /password_resets/:token" do
    let(:user) { create(:user) }
    let(:token) { user.password_reset_token }

    it "resets the password with valid token and valid password" do
      patch password_reset_path(token:),
            params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!" } }

      expect(response).to redirect_to(new_session_path)
      expect(user.reload.authenticate("NewPass123!")).to eq(user)
    end

    it "invalidates the token after successful reset" do
      patch password_reset_path(token:),
            params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!" } }

      found = User.find_by_token_for(:password_reset, token)
      expect(found).to be_nil
    end

    it "renders form with errors for mismatched confirmation" do
      patch password_reset_path(token:),
            params: { user: { password: "NewPass123!", password_confirmation: "Different1!" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "renders form with errors for weak password" do
      patch password_reset_path(token:),
            params: { user: { password: "weak", password_confirmation: "weak" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects for invalid token" do
      patch password_reset_path(token: "invalid"),
            params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!" } }

      expect(response).to redirect_to(new_password_reset_path)
    end

    it "redirects for expired token" do
      expired_token = user.password_reset_token
      Timecop.travel(3.hours.from_now) do
        patch password_reset_path(token: expired_token),
              params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!" } }

        expect(response).to redirect_to(new_password_reset_path)
      end
    end
  end
end
