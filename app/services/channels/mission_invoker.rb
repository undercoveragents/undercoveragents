# frozen_string_literal: true

module Channels
  class MissionInvoker
    class InvalidInvocation < StandardError; end

    def initialize(channel:, channel_target:)
      @channel = channel
      @channel_target = channel_target
      @mission = channel_target.target
    end

    def call(payload:, callback_url:, file_params:)
      raise InvalidInvocation, "Channel target is not a mission" unless @channel_target.target_type == "Mission"
      raise InvalidInvocation, "callback_url must be a valid HTTPS URL" if invalid_callback_url?(callback_url)

      run = create_run(payload, callback_url)
      updated_payload = attach_uploaded_files(run, payload, file_params)
      run.update!(trigger_data: updated_payload) if run.trigger_data != updated_payload
      ::Api::MissionExecutionJob.perform_later(run.id, tenant_id: @mission.operation.tenant_id)
      run
    end

    private

    def create_run(payload, callback_url)
      @mission.mission_runs.create!(
        status: :pending,
        flow_snapshot: @mission.flow_data,
        trigger_data: payload,
        callback_url:,
        channel: @channel,
        channel_target: @channel_target,
      )
    end

    def attach_uploaded_files(run, payload, file_params)
      file_names = @mission.file_field_names
      return payload if file_names.empty?

      updated_payload = payload.dup

      file_names.each do |name|
        files = file_params[name]
        next unless files

        blobs = Array(files).grep(ActionDispatch::Http::UploadedFile).map do |file|
          blob = ActiveStorage::Blob.create_and_upload!(
            io: file,
            filename: file.original_filename,
            content_type: file.content_type,
          )
          run.files.attach(blob)
          { filename: blob.filename.to_s, blob_id: blob.id }
        end
        next if blobs.empty?

        updated_payload[name] = blobs.size == 1 ? blobs.first : blobs
      end

      updated_payload
    end

    def invalid_callback_url?(callback_url)
      return false if callback_url.blank?

      uri = URI.parse(callback_url)
      !uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      true
    end
  end
end
