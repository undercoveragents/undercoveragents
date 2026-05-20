# frozen_string_literal: true

module Llm
  class ModelRoutingConfig
    class InvalidConfigError < ArgumentError; end

    DEFAULT_STRATEGY = "single"
    STRATEGIES = [DEFAULT_STRATEGY, "fallback", "canary", "ab_test"].freeze

    class << self
      def default
        { "strategy" => DEFAULT_STRATEGY }
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def normalize(value)
        raw = parse(value)
        return default if raw.blank?
        raise InvalidConfigError, "Model routing config must be a JSON object" unless raw.is_a?(Hash)

        normalized = {
          "strategy" => normalize_strategy(raw["strategy"]),
          "fallback_models" => normalize_routes(raw["fallback_models"]),
          "canary_model" => normalize_route(raw["canary_model"]),
          "canary_percent" => normalize_percent(raw["canary_percent"]),
          "comparison_model" => normalize_route(raw["comparison_model"]),
        }.compact

        normalized.delete("fallback_models") if normalized["fallback_models"].blank?
        normalized.delete("canary_model") if normalized["canary_model"].blank?
        normalized.delete("canary_percent") if normalized["canary_percent"].blank?
        normalized.delete("comparison_model") if normalized["comparison_model"].blank?
        normalized.presence || default
      rescue JSON::ParserError => e
        raise InvalidConfigError, "must be valid JSON (#{e.message})"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def persistable(value)
        normalized = normalize(value)
        normalized == default ? {} : normalized
      end

      def validate!(value, tenant: nil)
        config = normalize(value)
        errors = []
        strategy = config.fetch("strategy", DEFAULT_STRATEGY)

        errors << "strategy is not included in the list" unless strategy.in?(STRATEGIES)
        validate_fallback_config(config, errors) if strategy == "fallback"
        validate_canary_config(config, errors) if strategy == "canary"
        validate_ab_test_config(config, errors) if strategy == "ab_test"
        validate_route_connectors(config, tenant:, errors:)

        raise InvalidConfigError, errors.join(", ") if errors.any?

        config
      end

      private

      def parse(value)
        parsed = case value
                 when nil
                   {}
                 when String
                   stripped = value.strip
                   return {} if stripped.blank?

                   JSON.parse(stripped)
                 when Hash
                   value
                 else
                   return {} unless value.respond_to?(:to_h)

                   value.to_h
                 end

        parsed.respond_to?(:deep_stringify_keys) ? parsed.deep_stringify_keys : parsed
      end

      def normalize_strategy(value)
        value.to_s.presence || DEFAULT_STRATEGY
      end

      def normalize_routes(value)
        Array(value).filter_map { |route| normalize_route(route) }
      end

      def normalize_route(value)
        return if value.blank?
        raise InvalidConfigError, "Model route must be an object" unless value.respond_to?(:to_h)

        route = value.to_h.deep_stringify_keys.slice("connector_id", "model_id").compact_blank
        route["connector_id"] = Integer(route["connector_id"], exception: false) if route.key?("connector_id")
        route["model_id"] = route["model_id"].to_s.presence if route.key?("model_id")
        route.compact_blank.presence
      end

      def normalize_percent(value)
        return if value.blank?

        Integer(value)
      rescue ArgumentError, TypeError
        raise InvalidConfigError, "Canary percent must be an integer"
      end

      def validate_fallback_config(config, errors)
        return if config["fallback_models"].present?

        errors << "fallback_models must include at least one connector_id/model_id pair"
      end

      def validate_canary_config(config, errors)
        errors << "canary_model must include connector_id and model_id" unless route_complete?(config["canary_model"])
        percent = config["canary_percent"]
        errors << "canary_percent must be between 1 and 100" unless percent.is_a?(Integer) && percent.between?(
          1, 100,
        )
      end

      def validate_ab_test_config(config, errors)
        return if route_complete?(config["comparison_model"])

        errors << "comparison_model must include connector_id and model_id"
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      def validate_route_connectors(config, tenant:, errors:)
        return if tenant.blank?

        routes_for_validation(config).each do |label, route|
          next if route.blank?
          next if route["connector_id"].blank?

          connector = ConnectorLookup.find(route["connector_id"], tenant:)
          if connector.blank?
            errors << "#{label} connector is invalid"
            next
          end

          unless connector.connector_type == "llm_provider"
            errors << "#{label} connector must be an LLM Provider connector"
          end
          errors << "#{label} model_id can't be blank" if route["model_id"].blank?
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      def routes_for_validation(config)
        routes = []
        Array(config["fallback_models"]).each_with_index do |route, index|
          routes << ["fallback model ##{index + 1}", route]
        end
        routes << ["canary model", config["canary_model"]] if config["canary_model"].present?
        routes << ["comparison model", config["comparison_model"]] if config["comparison_model"].present?
        routes
      end

      def route_complete?(route)
        route.is_a?(Hash) && route["connector_id"].present? && route["model_id"].present?
      end
    end
  end
end
