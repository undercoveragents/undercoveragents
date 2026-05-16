# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDebugChannel do
  describe "#subscribed" do
    it "subscribes to the debug stream for the given run_id" do
      subscribe(run_id: "42")

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("#{Missions::DebugRunner::STREAM_PREFIX}_42")
    end
  end

  describe "#unsubscribed" do
    it "stops all streams on unsubscribe" do
      subscribe(run_id: "42")
      unsubscribe

      expect(subscription).not_to have_streams
    end
  end
end
