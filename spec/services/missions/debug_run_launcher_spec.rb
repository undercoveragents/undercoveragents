# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::DebugRunLauncher do
  subject(:launcher) do
    described_class.new(
      mission:,
      blob_url_resolver: ->(_blob) { "/rails/active_storage/blobs/test" },
      request_data:,
    )
  end

  let(:mission) { create(:mission) }
  let(:request_data) { { trigger_files: } }
  let(:trigger_files) { {} }

  describe "trigger file normalization" do
    it "uses to_h when the trigger files object exposes it" do
      wrapper = Struct.new(:value) do
        def to_h
          value
        end
      end

      request_data[:trigger_files] = wrapper.new({ "document" => [] })

      expect(launcher.send(:normalized_trigger_files)).to eq({ "document" => [] })
    end

    it "falls back to the raw object when no hash conversion helper exists" do
      raw_files = Object.new
      request_data[:trigger_files] = raw_files

      expect(launcher.send(:normalized_trigger_files)).to be(raw_files)
    end
  end
end
