# frozen_string_literal: true

module PlaygroundAccess
  extend ActiveSupport::Concern

  private

  def playground_available_agents
    @playground_available_agents ||= scoped_agents.enabled.selectable.ordered.to_a.select(&:playground_compatible?)
  end

  def playground_available_agent_ids
    @playground_available_agent_ids ||= playground_available_agents.map(&:id)
  end

  def find_playground_agent!(agent_id)
    return if agent_id.blank?

    agent = scoped_agents.enabled.selectable.friendly.find(agent_id)
    raise ActiveRecord::RecordNotFound unless playground_available_agent_ids.include?(agent.id)

    agent
  end

  def playground_chat_accessible?(chat)
    chat.agent_id.present? && playground_available_agent_ids.include?(chat.agent_id)
  end

  def playground_unavailable_alert
    I18n.t("playground.chats.no_available_agents.description")
  end
end
