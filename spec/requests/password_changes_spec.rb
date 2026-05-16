# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PasswordChanges" do
  let(:user) { User.find_by(role: "admin") }

  describe "GET /password_change/edit" do
    it "renders the change password form" do
      get edit_password_change_path
      expect(response).to have_http_status(:ok)
    end

    it "renders without layout for turbo frame requests" do
      get edit_password_change_path, headers: { "Turbo-Frame" => "password-change" }
      expect(response).to have_http_status(:ok)
    end

    context "when unauthenticated", :unauthenticated do
      it "redirects to login" do
        get edit_password_change_path
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "PATCH /password_change" do
    it "updates password with valid current password and new password" do
      patch password_change_path, params: {
        user: {
          current_password: "Password123!",
          password: "NewSecure1!",
          password_confirmation: "NewSecure1!",
        },
      }

      expect(response).to redirect_to(root_path)
      expect(user.reload.authenticate("NewSecure1!")).to eq(user)
    end

    it "responds with a turbo_stream navigate action for turbo frame requests" do
      patch password_change_path,
            params: {
              user: {
                current_password: "Password123!",
                password: "NewSecure1!",
                password_confirmation: "NewSecure1!",
              },
            },
            headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-stream")
    end

    it "shows success message" do
      patch password_change_path, params: {
        user: {
          current_password: "Password123!",
          password: "NewSecure1!",
          password_confirmation: "NewSecure1!",
        },
      }

      follow_redirect!
      expect(response.body).to include("password has been updated")
    end

    it "fails with incorrect current password" do
      patch password_change_path, params: {
        user: {
          current_password: "WrongPass1!",
          password: "NewSecure1!",
          password_confirmation: "NewSecure1!",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "fails with mismatched confirmation" do
      patch password_change_path, params: {
        user: {
          current_password: "Password123!",
          password: "NewSecure1!",
          password_confirmation: "Different1!",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "fails with weak new password" do
      patch password_change_path, params: {
        user: {
          current_password: "Password123!",
          password: "weak",
          password_confirmation: "weak",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "fails when new password lacks complexity" do
      patch password_change_path, params: {
        user: {
          current_password: "Password123!",
          password: "alllowercase1!",
          password_confirmation: "alllowercase1!",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
