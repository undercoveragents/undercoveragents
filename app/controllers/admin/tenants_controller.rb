# frozen_string_literal: true

module Admin
  class TenantsController < BaseController
    before_action :require_system_admin
    before_action :set_tenant, only: [:edit, :update, :destroy]

    def index
      @tenant_admin_credentials = session.delete(:tenant_admin_credentials)&.with_indifferent_access
      @tenants = Tenant.ordered.load
      load_index_counts
      authorize Tenant
    end

    def new
      @tenant = Tenant.new
      authorize @tenant
    end

    def edit
      authorize @tenant
    end

    def create
      @tenant = build_tenant_from_params
      authorize @tenant

      initial_admin = @tenant.build_initial_admin(email: @tenant.admin_email)
      return render(:new, status: :unprocessable_content) unless tenant_submission_valid?(initial_admin)

      persist_tenant_with_admin!
      redirect_to admin_tenants_path, notice: t("tenants.created")
    end

    def update
      authorize @tenant

      if @tenant.update(tenant_params)
        redirect_to admin_tenants_path, notice: t("tenants.updated")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @tenant

      if @tenant.default_tenant?
        redirect_to admin_tenants_path, alert: t("tenants.default_tenant_cannot_delete")
        return
      end

      @tenant.purge!
      redirect_to admin_tenants_path, notice: t("tenants.deleted"), status: :see_other
    end

    private

    def require_system_admin
      return if current_user.system_admin?

      redirect_to admin_root_path, alert: t("shared.not_authorized")
    end

    def load_index_counts
      tenant_ids = @tenants.map(&:id)

      @tenant_user_counts = count_records_by_tenant(User, tenant_ids)
      @tenant_operation_counts = count_records_by_tenant(Operation, tenant_ids)
      @tenant_connector_counts = count_records_by_tenant(Connector, tenant_ids)
      @tenant_client_counts = count_records_by_tenant(Client, tenant_ids)
    end

    def count_records_by_tenant(model_class, tenant_ids)
      return {} if tenant_ids.empty?

      model_class.where(tenant_id: tenant_ids).group(:tenant_id).count
    end

    def set_tenant
      @tenant = Tenant.friendly.find(params.expect(:id))
    end

    def tenant_params
      tenant_form_params.except(:admin_email)
    end

    def build_tenant_from_params
      Tenant.new(tenant_params).tap do |tenant|
        tenant.admin_email = admin_email_param
      end
    end

    def admin_email_param
      tenant_form_params[:admin_email]
    end

    def tenant_form_params
      params.expect(tenant: [:name, :description, :admin_email])
    end

    def merge_initial_admin_errors(initial_admin)
      initial_admin.errors.each do |error|
        attribute = error.attribute == :email ? :admin_email : error.attribute
        @tenant.errors.add(attribute, error.message)
      end
    end

    def tenant_submission_valid?(initial_admin)
      tenant_valid = @tenant.valid?
      admin_valid = initial_admin.valid?
      merge_initial_admin_errors(initial_admin) unless admin_valid

      tenant_valid && admin_valid
    end

    def persist_tenant_with_admin!
      admin_credentials = nil

      Tenant.transaction do
        @tenant.save!
        @tenant.ensure_core_resources!
        admin_credentials = @tenant.create_initial_admin_with_email!(email: @tenant.admin_email)
      end

      store_tenant_admin_credentials!(admin_credentials)
    end

    def store_tenant_admin_credentials!(admin_credentials)
      flash[:tenant_admin_credentials] = {
        tenant_name: @tenant.name,
        email: admin_credentials.user.email,
        password: admin_credentials.password,
      }
      session[:tenant_admin_credentials] = flash[:tenant_admin_credentials]
    end
  end
end
