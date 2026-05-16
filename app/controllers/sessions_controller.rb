# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :create]
  before_action :set_login_tenant, only: [:new, :create]
  before_action :persist_oauth_login_tenant_context, only: [:new, :create]
  before_action :clear_pending_cloud_signup_context, only: [:new, :create]
  layout "auth"

  def new
    redirect_to root_path if current_user
  end

  def create
    user = login_user_scope.find_by("LOWER(email) = ?", normalized_email)

    if user&.authenticate(params[:password])
      start_session_for(user)
    else
      flash.now[:alert] = t("auth.invalid_credentials")
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path, notice: t("auth.signed_out")
  end

  private

  def start_session_for(user)
    unless user.active?
      flash.now[:alert] = t("auth.account_inactive")
      render :new, status: :unprocessable_content
      return
    end

    return_to = session[:return_to]
    reset_session
    bootstrap_session_for(user)
    redirect_to return_to || default_path_after_sign_in(user), notice: t("auth.signed_in")
  end

  def set_login_tenant
    return if params[:tenant_id].blank?

    @login_tenant = Tenant.friendly.find(params.expect(:tenant_id))
  end

  def login_user_scope
    @login_tenant ? @login_tenant.users : User
  end

  def normalized_email
    params.fetch(:email, nil)&.downcase&.strip
  end

  def persist_oauth_login_tenant_context
    if @login_tenant.present?
      session[:oauth_login_tenant_id] = @login_tenant.id
    else
      session.delete(:oauth_login_tenant_id)
    end
  end

  def clear_pending_cloud_signup_context
    Cloud::PendingSignup.clear(session)
  end
end
