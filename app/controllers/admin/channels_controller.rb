# frozen_string_literal: true

module Admin
  class ChannelsController < BaseController
    include ChannelPreviewRendering
    include ChannelTargetManagement
    include ChatUiSupport
    include Toggleable

    UPCOMING_CHANNEL_PLACEHOLDERS = [
      {
        label: "Forms",
        icon: "fa-solid fa-clipboard-list",
        description: "Structured submission flows backed by missions.",
      },
      {
        label: "Slack",
        icon: "fa-brands fa-slack",
        description: "Team conversations, mentions, and threaded follow-up.",
      },
      {
        label: "WhatsApp",
        icon: "fa-brands fa-whatsapp",
        description: "Business messaging with channel identities and routing.",
      },
      {
        label: "Teams",
        icon: "fa-brands fa-microsoft",
        description: "Microsoft Teams chat delivery for workspace assistants.",
      },
    ].freeze

    before_action :set_channel, only: [:show, :edit, :update, :destroy, :toggle, :regenerate_token]

    def index
      authorize Channel
      @channels = channel_scope.ordered.to_a
      preload_channel_index_associations(@channels)
    end

    def show
      authorize @channel

      render_preview if client_preview_request?
    end

    def new
      requested_type = requested_channel_type
      return render_type_selection unless requested_type

      @channel = current_operation.channels.new(
        tenant: current_tenant,
        channel_type: requested_type,
        enabled: true,
        default: !channel_scope.by_type(requested_type).exists?,
      )
      authorize @channel
      load_form_data
    end

    def edit
      authorize @channel
      load_form_data
    end

    def create
      @channel = build_channel
      authorize @channel

      persist_channel(notice: t("channels.created"), failure_template: :new)
    end

    def update
      authorize @channel
      @channel.assign_attributes(channel_params.except(:channel_type))
      assign_type_params(@channel, @channel.channel_type)

      persist_channel(notice: t("channels.updated"), failure_template: :edit)
    end

    def destroy
      authorize @channel

      @channel.destroy!
      redirect_to admin_channels_path, notice: t("channels.deleted"), status: :see_other
    end

    def regenerate_token
      authorize @channel

      raw_token = primary_credential.regenerate_token!
      flash[:channel_token] = raw_token
      redirect_to admin_channel_path(@channel), notice: t("channels.token_regenerated")
    end

    def toggle = super

    def toggle_record = @channel
    def toggle_redirect_path = admin_channels_path
    def toggle_i18n_prefix = "channels"

    private

    def set_channel
      @channel = channel_scope.friendly.find(params.expect(:id))
    end

    def channel_scope
      scoped_channels.where(channel_type: ChannelPlugin.type_keys)
    end

    def build_channel
      channel = current_operation.channels.new(channel_params.merge(tenant: current_tenant))
      assign_type_params(channel, channel.channel_type)
      channel
    end

    def preload_channel_index_associations(channels)
      ActiveRecord::Associations::Preloader.new(
        records: channels,
        associations: :channel_targets,
      ).call
      ActiveRecord::Associations::Preloader.new(
        records: channels,
        associations: :logo_attachment,
      ).call
    end

    def persist_channel(notice:, failure_template:)
      ActiveRecord::Base.transaction do
        ensure_single_default_channel
        @channel.save!
        sync_targets!
        ensure_primary_credential!
      end

      redirect_to admin_channel_path(@channel), notice:
    rescue ActiveRecord::RecordInvalid
      load_form_data
      render failure_template, status: :unprocessable_content
    end

    def channel_params
      permitted = params.expect(channel: [:name, :description, :channel_type, :connector_id, :enabled, :default, :logo])
      permitted[:connector_id] = nil if permitted[:connector_id].blank?
      permitted
    end

    def requested_channel_type
      type = params[:type].presence || params.dig(:channel, :channel_type).presence
      ChannelPlugin.type_keys.include?(type) ? type : nil
    end

    def assign_type_params(channel, type_key)
      klass = ChannelPlugin.resolve(type_key)
      return unless klass

      klass.permitted_params(params).each do |attribute, value|
        channel.public_send(:"#{attribute}=", value)
      end
    end

    def ensure_primary_credential!
      return unless credential_channel?
      return if @channel.channel_credentials.exists?

      credential = @channel.channel_credentials.create!(name: "Primary token", credential_type: primary_credential_type)
      flash[:channel_token] = credential.raw_token if credential.raw_token.present?
    end

    def primary_credential
      @primary_credential ||= @channel.channel_credentials.first_or_create!(
        name: "Primary token",
        credential_type: primary_credential_type,
      )
    end

    def credential_channel?
      @channel.api_channel?
    end

    def primary_credential_type
      "bearer_token"
    end

    def render_type_selection
      authorize Channel
      @channel_types = ChannelPlugin.all_types
      @channel_placeholders = UPCOMING_CHANNEL_PLACEHOLDERS
      render :new
    end
  end
end
