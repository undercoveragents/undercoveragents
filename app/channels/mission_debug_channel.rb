# frozen_string_literal: true

# ActionCable channel for real-time mission debug execution events.
# The React designer subscribes with a run_id and receives JSON events
# as each node executes: node:started, node:completed, variables:changed, run:status.
class MissionDebugChannel < ApplicationCable::Channel
  def subscribed
    stream_from stream_name
  end

  def unsubscribed
    stop_all_streams
  end

  private

  def stream_name
    "#{Missions::DebugRunner::STREAM_PREFIX}_#{params[:run_id]}"
  end
end
