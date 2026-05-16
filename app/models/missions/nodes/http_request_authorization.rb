# frozen_string_literal: true

module Missions
  module Nodes
    module HttpRequestAuthorization
      private

      def apply_authorization!(headers, params, context, node_data)
        auth_type = normalized_auth_type(node_data)
        return if auth_type == "none"

        return apply_bearer_authorization!(headers, context, node_data) if auth_type == "bearer"
        return apply_basic_authorization!(headers, context, node_data) if auth_type == "basic"

        apply_api_key_authorization!(headers, params, context, node_data)
      end

      def apply_bearer_authorization!(headers, context, node_data)
        token = stringify_value(resolve_value(context, node_data["auth_bearer_token"]))
        headers["Authorization"] = "Bearer #{token}" if token.present?
      end

      def apply_basic_authorization!(headers, context, node_data)
        username = stringify_value(resolve_value(context, node_data["auth_username"]))
        password = stringify_value(resolve_value(context, node_data["auth_password"]))
        return if username.blank? && password.blank?

        credentials = Base64.strict_encode64("#{username}:#{password}")
        headers["Authorization"] = "Basic #{credentials}"
      end

      def apply_api_key_authorization!(headers, params, context, node_data)
        key = context.interpolate(node_data["auth_api_key_name"].to_s).strip
        value = stringify_value(resolve_value(context, node_data["auth_api_key_value"]))
        return if key.blank? || value.blank?

        if node_data["auth_api_key_in"].to_s == "query"
          params[key] = value
        else
          headers[key] = value
        end
      end

      def normalized_auth_type(node_data)
        auth_type = node_data["auth_type"].to_s
        self.class::ALLOWED_AUTH_TYPES.include?(auth_type) ? auth_type : "none"
      end
    end
  end
end
