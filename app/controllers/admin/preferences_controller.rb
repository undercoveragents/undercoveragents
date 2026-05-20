# frozen_string_literal: true

module Admin
  class PreferencesController < BaseController
    include ModelOptionsSupport

    def show
      @preference = current_system_preference
      authorize @preference
      load_form_data
    end

    def update
      @preference = current_system_preference
      authorize @preference
      attrs = preference_params.to_h

      clear_pair!(attrs, :llm_connector_id, :model_id)
      clear_pair!(attrs, :embedding_connector_id, :embedding_model_id)
      clear_pair!(attrs, :image_connector_id, :image_model_id)

      @preference.assign_attributes(attrs)

      if @preference.save
        redirect_to admin_root_path, notice: t("preferences.updated")
      else
        load_form_data
        render :show, status: :unprocessable_content
      end
    end

    private

    def load_form_data
      @llm_connectors = scoped_connectors.llm_providers.enabled.ordered
      @available_models = models_for_connector(@preference.llm_connector_id)
      @available_embedding_models = models_for_connector(@preference.embedding_connector_id)
      @available_image_models = models_for_connector(@preference.image_connector_id)
    end

    def preference_params
      params.expect(
        system_preference: [
          :llm_connector_id, :model_id, :temperature, :thinking_effort, :thinking_budget, :custom_llm_params,
          :model_routing_config,
          :embedding_connector_id, :embedding_model_id,
          :image_connector_id, :image_model_id,
        ],
      )
    end

    def clear_pair!(attrs, connector_key, model_key)
      return if attrs[connector_key].present?

      attrs[connector_key] = nil
      attrs[model_key] = nil
    end
  end
end
