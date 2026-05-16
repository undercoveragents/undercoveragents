# frozen_string_literal: true

class OmniauthCallbacksController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :set_oauth_login_tenant, only: [:create, :failure]
  before_action :set_pending_cloud_signup, only: [:create, :failure]

  def create
    auth = request.env["omniauth.auth"]
    user = find_or_create_user(auth, tenant: @oauth_login_tenant, pending_signup: @pending_cloud_signup)

    return sign_in_user(user) if user.persisted? && user.active?

    redirect_to failure_redirect_path(auth), alert: failure_alert_message
  ensure
    clear_oauth_login_tenant_context
    clear_pending_cloud_signup_context
  end

  def failure
    redirect_to login_path_for(@oauth_login_tenant, pending_signup: @pending_cloud_signup),
                alert: t("auth.oauth_failure", reason: failure_message)
  ensure
    clear_oauth_login_tenant_context
    clear_pending_cloud_signup_context
  end

  private

  def find_or_create_user(auth, tenant: nil, pending_signup: nil)
    return create_cloud_signup_user(auth, pending_signup) if pending_signup.present?
    return find_or_create_tenant_scoped_user(auth, tenant) if tenant.present?

    find_generic_oauth_user(auth)
  end

  def create_cloud_signup_user(auth, pending_signup)
    return User.new unless auth.provider == pending_signup.provider

    result = Cloud::TenantSignupService.new(
      admin_email: auth.info.email,
      oauth_identity: { provider: auth.provider, uid: auth.uid },
    ).call

    @pending_cloud_signup_errors = result.errors
    result.user
  end

  def find_generic_oauth_user(auth)
    user = User.find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    @oauth_login_errors = [t("auth.oauth_tenant_login_required")]
    User.new
  end

  def find_or_create_tenant_scoped_user(auth, tenant)
    user = tenant.users.find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    user = tenant.users.find_by("LOWER(email) = ?", auth.info.email&.downcase)
    if user
      user.update!(provider: auth.provider, uid: auth.uid)
      return user
    end

    User.new
  end

  def failure_message
    params.fetch(:message, nil).to_s.humanize
  end

  def set_oauth_login_tenant
    @oauth_login_tenant = Tenant.find_by(id: session[:oauth_login_tenant_id])
  end

  def set_pending_cloud_signup
    pending_cloud_signup = Cloud::PendingSignup.load(session)
    pending_cloud_signup ||= Cloud::PendingSignup.from_request_params(request.env["omniauth.params"] || {})
    pending_cloud_signup ||= Cloud::PendingSignup.from_request_params(params)
    @pending_cloud_signup = pending_cloud_signup
  end

  def clear_oauth_login_tenant_context
    session.delete(:oauth_login_tenant_id)
  end

  def clear_pending_cloud_signup_context
    Cloud::PendingSignup.clear(session)
  end

  def login_path_for(tenant, pending_signup: nil, email: nil)
    if pending_signup.present?
      params = {}
      params[:email] = email if email.present?
      return params.present? ? new_cloud_signup_path(params) : new_cloud_signup_path
    end

    tenant ? tenant_login_path(tenant) : new_session_path
  end

  def failure_redirect_path(auth)
    email = auth.info.email

    login_path_for(@oauth_login_tenant, pending_signup: @pending_cloud_signup, email:)
  end

  def failure_alert_message
    Array(@pending_cloud_signup_errors).to_sentence.presence ||
      Array(@oauth_login_errors).to_sentence.presence ||
      t("auth.oauth_error")
  end

  def sign_in_user(user)
    reset_session
    bootstrap_session_for(user)
    redirect_to default_path_after_sign_in(user), notice: t("auth.signed_in")
  end
end
