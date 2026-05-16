# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:edit, :update, :destroy]

    def index
      authorize User
      @users = users_scope.ordered
    end

    def new
      @user = users_scope.new(tenant: default_form_tenant)
      authorize @user
      load_form_data
    end

    def edit
      authorize @user
      load_form_data
    end

    def create
      @user = User.new(user_params)
      @user.tenant ||= default_form_tenant
      authorize @user

      if @user.save
        redirect_to admin_users_path, notice: t("admin.users.created")
      else
        load_form_data
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @user
      sanitized_params = user_params
      sanitized_params = sanitized_params.except(:password) if sanitized_params[:password].blank?

      if @user.update(sanitized_params)
        redirect_to admin_users_path, notice: t("admin.users.updated")
      else
        load_form_data
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @user

      if @user == current_user
        redirect_to admin_users_path, alert: t("admin.users.cannot_delete_self")
        return
      end

      @user.destroy!
      redirect_to admin_users_path, notice: t("admin.users.deleted"), status: :see_other
    end

    private

    def set_user
      @user = users_scope.find(params.expect(:id))
    end

    def user_params
      attrs = params.expect(user: [:email, :password, :role, :status])
      attrs[:tenant_id] = current_tenant.id
      attrs[:role] = normalize_role(attrs[:role])
      attrs
    end

    def users_scope
      current_tenant.users
    end

    def available_roles
      current_user.system_admin? ? User.roles.keys : ["user", "admin"]
    end

    def load_form_data
      @available_roles = available_roles
    end

    def normalize_role(role)
      available_roles.include?(role) ? role : "user"
    end

    def default_form_tenant
      current_tenant
    end
  end
end
