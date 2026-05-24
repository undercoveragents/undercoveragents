# frozen_string_literal: true

module ManageRecordAgentTypeDefaulting
  private

  def normalize_create_attributes(resource, attributes)
    return attributes unless resource.to_s == "agent"
    return attributes unless agent_designer_create?

    parsed_attributes = parse_attributes_for_normalization(attributes)
    return attributes unless parsed_attributes.is_a?(Hash)

    requested_type = parsed_attributes["agent_type"].to_s.presence
    normalized_agent_type_attributes(parsed_attributes, requested_type)
  end

  def agent_designer_create?
    agent = @runtime_context.agent
    agent&.builtin_key == "agent_designer" || agent&.agent_type == "agent_designer"
  end

  def parse_attributes_for_normalization(attributes)
    case attributes
    when ActionController::Parameters
      attributes.to_unsafe_h.stringify_keys
    when Hash
      attributes.stringify_keys
    when String
      parsed = JSON.parse(attributes)
      parsed.is_a?(Hash) ? parsed.stringify_keys : attributes
    else
      attributes
    end
  end

  def explicit_agent_type_request?(requested_type)
    request_text = latest_user_request_text
    return false if request_text.blank?

    normalized_request = normalize_agent_type_text(request_text)
    agent_type_candidates(requested_type).any? do |candidate|
      normalized_request.include?(normalize_agent_type_text(candidate))
    end
  end

  def latest_user_request_text
    chat = @runtime_context.chat
    return "" unless chat

    chat.messages.where(role: :user).order(:id).last&.content.to_s
  end

  def agent_type_candidates(requested_type)
    [requested_type, requested_type.tr("_", " "), requested_type.to_s.humanize].uniq
  end

  def normalize_agent_type_text(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  def provider_agent_type?(value)
    AgentConfiguration.provider_agent_type?(value)
  end

  def normalized_agent_type_attributes(parsed_attributes, requested_type)
    return parsed_attributes if requested_type.blank? || requested_type == AgentConfiguration::DEFAULT_AGENT_TYPE
    return default_agent_type_attributes(parsed_attributes) if provider_agent_type?(requested_type)
    return parsed_attributes if explicit_agent_type_request?(requested_type)

    default_agent_type_attributes(parsed_attributes)
  end

  def default_agent_type_attributes(parsed_attributes)
    parsed_attributes.merge("agent_type" => AgentConfiguration::DEFAULT_AGENT_TYPE)
  end
end
