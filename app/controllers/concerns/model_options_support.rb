# frozen_string_literal: true

# Shared logic for rendering model option select lists in tool forms.
# Handles connector → models lookup and turbo frame rendering.
module ModelOptionsSupport
  extend ActiveSupport::Concern

  private

  # Renders a model_select partial using the given configuration hash.
  # Config keys: :frame_id, :field_prefix, :filter (optional), :field_name (optional).
  def render_model_options(config)
    available_models = models_for_connector(params[:connector_id], filter: config[:filter])

    locals = {
      frame_id: config[:frame_id],
      field_prefix: config[:field_prefix],
      available_models:,
      selected_model_id: params[:selected_model_id].presence,
    }
    locals[:field_name] = config[:field_name] if config[:field_name]
    locals[:required] = config[:required] if config.key?(:required)
    if config[:llm_settings]
      locals[:frame_data] = {
        llm_settings_target: "modelFrame",
        action: "turbo:frame-load->llm-settings#syncCapabilities",
      }
      locals[:select_action] = "change->llm-settings#syncCapabilities"
    end

    render partial: "shared/model_select", locals:
  end

  def models_for_connector(connector_id, filter: nil)
    connector = scoped_connectors.find_by(id: connector_id)
    provider = connector.provider if connector&.connector_type == "llm_provider"

    return Model.none if provider.blank?

    scope = Model.where(provider:).order(:name).picker_projection
    scope = scope.where("modalities -> 'output' @> '\"embeddings\"'") if filter == :embedding
    scope = scope.where("modalities -> 'output' @> '\"image\"'") if filter == :image
    scope
  end
end
