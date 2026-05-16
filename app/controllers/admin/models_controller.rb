# frozen_string_literal: true

module Admin
  class ModelsController < BaseController
    SORT_COLUMNS = {
      "provider" => :provider,
      "name" => :name,
      "family" => :family,
      "context_window" => :context_window,
      "max_output_tokens" => :max_output_tokens,
      "knowledge_cutoff" => :knowledge_cutoff,
      "model_created_at" => :model_created_at,
      "model_id" => :model_id,
    }.freeze
    TABLE_COLUMNS = {
      "provider" => "Provider",
      "name" => "Name",
      "context_window" => "Context Window",
    }.freeze
    FACET_CONFIGS = [
      { key: :provider, title: "Providers", icon: "fa-solid fa-building" },
      { key: :capability, title: "Capabilities", icon: "fa-solid fa-bolt" },
      { key: :input_modality, title: "Input Modalities", icon: "fa-solid fa-arrow-right-to-bracket" },
      { key: :output_modality, title: "Output Modalities", icon: "fa-solid fa-arrow-right-from-bracket" },
    ].freeze

    def index
      @filters = permitted_filter_params.to_h.compact_blank.symbolize_keys
      filtered_scope = apply_filters(Model.all, @filters)

      @sort_column = sort_column
      @sort_direction = sort_direction
      @table_columns = TABLE_COLUMNS
      @total_models_count = Model.count
      @filtered_models_count = filtered_scope.count
      @facet_groups = build_facet_groups
      @pagy, @models = pagy(:offset, apply_sort(filtered_scope), limit: 50)
    end

    def refresh
      ModelRefreshJob.perform_later
      redirect_to admin_models_path, notice: t("models.refresh_started")
    end

    private

    def permitted_filter_params
      params.permit(:search, :provider, :capability, :input_modality, :output_modality)
    end

    def build_facet_groups
      FACET_CONFIGS.map do |config|
        scope = apply_filters(Model.all, @filters.except(config[:key]))

        {
          key: config[:key],
          title: config[:title],
          icon: config[:icon],
          all_count: scope.count,
          options: facet_options(scope, config[:key]),
        }
      end
    end

    def facet_options(scope, facet_key)
      counts = Hash.new(0)

      scope.select(:provider, :family, :capabilities, :modalities).each do |model_record|
        facet_values_for(model_record, facet_key).each do |value|
          counts[value] += 1 if value.present?
        end
      end

      counts
        .sort_by { |value, count| [-count, value.to_s.downcase] }
        .map { |value, count| { value:, count: } }
    end

    def facet_values_for(model_record, facet_key)
      case facet_key
      when :provider then Array(model_record.provider)
      when :capability then Array(model_record.capabilities)
      when :input_modality then modalities_for(model_record, "input")
      when :output_modality then modalities_for(model_record, "output")
      else []
      end
    end

    def modalities_for(model_record, key)
      return [] unless model_record.modalities.is_a?(Hash)

      Array(model_record.modalities[key])
    end

    def apply_filters(scope, filters)
      scope = apply_text_search(scope, filters[:search])
      scope = apply_scalar_filters(scope, filters)
      apply_json_filters(scope, filters)
    end

    def apply_text_search(scope, search)
      return scope if search.blank?

      query = "%#{Model.sanitize_sql_like(search)}%"
      scope.where(
        "name ILIKE :query OR model_id ILIKE :query OR provider ILIKE :query OR COALESCE(family, '') ILIKE :query",
        query:,
      )
    end

    def apply_scalar_filters(scope, filters)
      scope = scope.where(provider: filters[:provider]) if filters[:provider].present?
      scope
    end

    def apply_json_filters(scope, filters)
      scope = apply_json_array_filter(scope, :capabilities, filters[:capability])
      scope = apply_json_array_filter(scope, :input_modality, filters[:input_modality])
      apply_json_array_filter(scope, :output_modality, filters[:output_modality])
    end

    def apply_json_array_filter(scope, filter_key, value)
      return scope if value.blank?

      case filter_key
      when :capabilities
        scope.where("capabilities @> ?", [value].to_json)
      when :input_modality
        scope.where("modalities -> 'input' @> ?", [value].to_json)
      when :output_modality
        scope.where("modalities -> 'output' @> ?", [value].to_json)
      else
        scope
      end
    end

    def apply_sort(scope)
      ordered_scope = scope.order(sort_column => sort_direction.to_sym)
      ordered_scope = ordered_scope.order(provider: :asc) unless sort_column == "provider"
      ordered_scope = ordered_scope.order(model_id: :asc) unless sort_column == "model_id"
      ordered_scope
    end

    def sort_column
      requested_column = params.fetch(:sort, nil).to_s
      SORT_COLUMNS.key?(requested_column) ? requested_column : "provider"
    end

    def sort_direction
      requested_direction = params.fetch(:direction, nil).to_s
      ["asc", "desc"].include?(requested_direction) ? requested_direction : "asc"
    end
  end
end
