# frozen_string_literal: true

module PlaygroundHelper
  include ChatUiHelper

  def playground_agents_for_select(agents)
    agents.map { |a| [a.name, a.id] }
  end
end
