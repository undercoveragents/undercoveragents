# frozen_string_literal: true

class PasswordResetsController < ApplicationController
  skip_before_action :require_authentication
  layout "auth"

  def new
    redirect_to root_path if current_user
  end

  def edit
    @user = User.find_by_token_for(:password_reset, params[:token])
    return if @user

    redirect_to new_password_reset_path, alert: t("auth.password_reset.invalid_token")
  end

  def create
    user = User.local_accounts.active.find_by("LOWER(email) = ?", params.fetch(:email, nil)&.downcase&.strip)

    if user
      token = user.password_reset_token
      UserMailer.password_reset(user, token).deliver_later
    end

    # Always show the same message to prevent email enumeration
    redirect_to new_session_path, notice: t("auth.password_reset.email_sent")
  end

  def update
    @user = User.find_by_token_for(:password_reset, params[:token])

    unless @user
      redirect_to new_password_reset_path, alert: t("auth.password_reset.invalid_token")
      return
    end

    if @user.update(password_params)
      redirect_to new_session_path, notice: t("auth.password_reset.success")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def password_params
    params.expect(user: [:password, :password_confirmation])
  end
end
