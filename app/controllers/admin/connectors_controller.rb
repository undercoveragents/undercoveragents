# frozen_string_literal: true

module Admin
  class ConnectorsController < BaseController
    include Toggleable

    before_action :set_connector, only: [:show, :edit, :update, :destroy, :toggle]

    def index
      authorize Connector
      @connectors = scoped_connectors.ordered
    end

    def show
      authorize @connector
    end

    def new
      authorize Connector
      @connector_type = params[:type]
    end

    def edit
      authorize @connector
      @connector_type = @connector.connector_type
    end

    def create
      @connector = build_connector
      authorize @connector

      if @connector.save
        redirect_to admin_connector_path(@connector), notice: t("connectors.created")
      else
        @connector_type = params[:connector_type]
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @connector

      assign_type_params(@connector, @connector.connector_type)
      @connector.assign_attributes(connector_params)

      @connector.save!
      redirect_to admin_connector_path(@connector), notice: t("connectors.updated")
    rescue ActiveRecord::RecordInvalid
      @connector_type = @connector.connector_type
      render :edit, status: :unprocessable_content
    end

    def destroy
      authorize @connector
      @connector.destroy!
      redirect_to admin_connectors_path, notice: t("connectors.deleted"), status: :see_other
    end

    def toggle = super
    def toggle_record = @connector
    def toggle_redirect_path = admin_connectors_path
    def toggle_i18n_prefix = "connectors"

    def provider_fields
      saved_prefixes = lookup_context.prefixes
      authorize Connector, :provider_fields?
      connector = Connectors::LlmProvider.new(provider: params[:provider])
      prepend_view_path(connector.form_partial_path)
      lookup_context.prefixes = [""]
      render partial: "llm_provider_provider_fields", locals: { connector: }, layout: false
    ensure
      lookup_context.prefixes = saved_prefixes
    end

    private

    def set_connector
      @connector = scoped_connectors.friendly.find(params.expect(:id))
    end

    def connector_params
      params.expect(connector: [:name, :description, :enabled])
    end

    def build_connector
      type_key = params[:connector_type]
      connector = current_tenant.connectors.new(connector_params)
      connector.connector_type = type_key
      assign_type_params(connector, type_key)
      connector
    end

    def assign_type_params(connector, type_key)
      klass = ConnectorPlugin.resolve(type_key)
      return unless klass

      type_params = klass.permitted_params(params)
      type_params.each { |k, v| connector.send(:"#{k}=", v) }
    end
  end
end
