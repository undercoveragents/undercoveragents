# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::MissionInvoker do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:mission) { create(:mission, operation:) }
  let(:channel) { create(:channel, :api, tenant:) }
  let(:channel_target) { create(:channel_target, :mission, channel:, target: mission, default: true) }

  def uploaded_file(name:, content: "hello")
    tempfile = Tempfile.new([File.basename(name, ".*"), File.extname(name)])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile:,
      filename: name,
      type: "text/plain",
    )
  end

  describe "#call" do
    it "creates a mission run and enqueues execution" do
      run = nil

      expect do
        run = described_class.new(channel:, channel_target:).call(
          payload: { "input" => "hello" },
          callback_url: "",
          file_params: {},
        )
      end.to change(MissionRun, :count).by(1)
         .and have_enqueued_job(Api::MissionExecutionJob).with(kind_of(Integer), tenant_id: tenant.id)

      expect(run.channel).to eq(channel)
      expect(run.channel_target).to eq(channel_target)
      expect(run.trigger_data).to eq({ "input" => "hello" })
    end

    it "attaches a single uploaded file and stores its blob metadata in trigger data" do
      file = uploaded_file(name: "brief.txt")
      allow(mission).to receive(:file_field_names).and_return(["attachment"])

      run = described_class.new(channel:, channel_target:).call(
        payload: { "input" => "hello" },
        callback_url: nil,
        file_params: { "attachment" => file },
      )

      expect(run.files.count).to eq(1)
      expect(run.trigger_data["attachment"]).to include("filename" => "brief.txt")
      expect(run.trigger_data["attachment"]["blob_id"]).to be_present
    ensure
      file.tempfile.close!
    end

    it "stores arrays of uploaded file metadata when multiple files are submitted" do
      first_file = uploaded_file(name: "first.txt")
      second_file = uploaded_file(name: "second.txt")
      allow(mission).to receive(:file_field_names).and_return(["documents"])

      run = described_class.new(channel:, channel_target:).call(
        payload: {},
        callback_url: nil,
        file_params: { "documents" => [first_file, second_file] },
      )

      expect(run.files.count).to eq(2)
      expect(run.trigger_data["documents"].pluck("filename")).to eq(["first.txt", "second.txt"])
    ensure
      first_file.tempfile.close!
      second_file.tempfile.close!
    end

    it "ignores missing or non-upload file params" do
      allow(mission).to receive(:file_field_names).and_return(["attachment", "notes"])

      run = described_class.new(channel:, channel_target:).call(
        payload: { "input" => "hello" },
        callback_url: nil,
        file_params: { "notes" => ["text"] },
      )

      expect(run.files).to be_empty
      expect(run.trigger_data).to eq({ "input" => "hello" })
    end

    it "rejects non-mission targets" do
      agent_channel = create(:channel, :api, tenant:)
      agent_target = create(:channel_target, channel: agent_channel, target: create(:agent, operation:))

      expect do
        described_class.new(channel: agent_channel, channel_target: agent_target).call(
          payload: {},
          callback_url: nil,
          file_params: {},
        )
      end.to raise_error(described_class::InvalidInvocation, "Channel target is not a mission")
    end

    it "rejects non-https callback URLs" do
      expect do
        described_class.new(channel:, channel_target:).call(
          payload: {},
          callback_url: "http://example.com/callback",
          file_params: {},
        )
      end.to raise_error(described_class::InvalidInvocation, "callback_url must be a valid HTTPS URL")
    end

    it "treats malformed callback URLs as invalid" do
      invoker = described_class.new(channel:, channel_target:)

      expect(invoker.send(:invalid_callback_url?, "%%%")).to be(true)
      expect(invoker.send(:invalid_callback_url?, nil)).to be(false)
    end
  end
end
