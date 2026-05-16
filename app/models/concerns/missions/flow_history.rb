# frozen_string_literal: true

module Missions
  module FlowHistory
    extend ActiveSupport::Concern

    HISTORY_LIMIT = 50

    # Pushes +snapshot+ (a flow_data Hash) onto the undo stack and clears the redo stack.
    # Keeps at most HISTORY_LIMIT entries.
    def push_undo_snapshot!(snapshot)
      history = (flow_undo_history || []).last(HISTORY_LIMIT - 1)
      update_columns(flow_undo_history: history + [snapshot], flow_redo_history: []) # rubocop:disable Rails/SkipsModelValidations
    end

    def can_undo? = (flow_undo_history || []).any?
    def can_redo? = (flow_redo_history || []).any?
  end
end
