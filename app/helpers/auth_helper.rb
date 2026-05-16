# frozen_string_literal: true

module AuthHelper
  def auth_provider_label(provider)
    case provider
    when "keycloak_openid", "keycloak" then "Keycloak"
    else provider&.titleize || "Unknown"
    end
  end

  def auth_provider_icon(provider)
    case provider
    when "keycloak_openid", "keycloak" then "fa-solid fa-key"
    else "fa-solid fa-right-to-bracket"
    end
  end
end
