# frozen_string_literal: true

class PasswordChangesController < ApplicationController
  layout -> { turbo_frame_request? ? false : "application" }

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    unless @user.authenticate(params[:user][:current_password])
      @user.errors.add(:current_password, t("auth.password_change.incorrect_current"))
      render :edit, status: :unprocessable_content
      return
    end

    if @user.update(password_params)
      flash[:notice] = t("auth.password_change.success")
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.action(:navigate, root_path) }
        format.html { redirect_to root_path }
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def password_params
    params.expect(user: [:password, :password_confirmation])
  end
end
