# frozen_string_literal: true

class CloudSignupsController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :create]
  before_action :redirect_signed_in_user, only: [:new, :create]
  before_action :clear_auth_contexts, only: [:new, :create]
  layout "auth"

  def new
    @admin_email = params.fetch(:email, nil).to_s
    @errors = []
  end

  def create
    result = Cloud::TenantSignupService.new(
      admin_email: signup_params[:admin_email],
      password: signup_params[:password],
      password_confirmation: signup_params[:password_confirmation],
    ).call

    return complete_signup_for(result.user) if result.success?

    @admin_email = signup_params[:admin_email].to_s.strip
    @errors = result.errors

    render :new, status: :unprocessable_content
  end

  private

  def signup_params
    params.expect(cloud_signup: [:admin_email, :password, :password_confirmation])
  end

  def redirect_signed_in_user
    return unless current_user

    redirect_to default_path_after_sign_in(current_user)
  end

  def clear_auth_contexts
    session.delete(:oauth_login_tenant_id)
    Cloud::PendingSignup.clear(session)
  end

  def complete_signup_for(user)
    reset_session
    bootstrap_session_for(user)

    redirect_to default_path_after_sign_in(user), notice: t("cloud_signup.created")
  end

  def google_oauth_enabled?
    Connectors::Authentication.enabled_for_provider?(Cloud::PendingSignup::PROVIDER)
  end
  helper_method :google_oauth_enabled?
end
