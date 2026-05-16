# frozen_string_literal: true

module Missions
  class DebugRunLauncher
    Result = Data.define(:run, :variables, :trigger_data)

    def initialize(mission:, blob_url_resolver:, request_data:)
      @mission = mission
      @blob_url_resolver = blob_url_resolver
      @request_data = request_data
    end

    def call
      persist_flow_data! if raw_flow_data.present?

      variables = parse_json(raw_variables)
      trigger_data = mission.filter_trigger_data(parse_json(raw_trigger_data))
      run = mission.mission_runs.create!(status: :pending, flow_snapshot: mission.flow_data, trigger_data:)
      trigger_data = attach_trigger_files(run, trigger_data)

      Result.new(run:, variables:, trigger_data:)
    end

    private

    attr_reader :blob_url_resolver, :mission, :request_data

    def raw_flow_data
      request_data[:flow_data]
    end

    def raw_variables
      request_data[:variables]
    end

    def raw_trigger_data
      request_data[:trigger_data]
    end

    def trigger_files
      request_data[:trigger_files]
    end

    def persist_flow_data!
      mission.update!(flow_data: Missions::FlowPersistenceNormalizer.parse_and_normalize(
        raw_flow_data,
        tenant: mission.operation.tenant,
      ))
    end

    def parse_json(value)
      return {} if value.blank?

      JSON.parse(value)
    rescue JSON::ParserError
      {}
    end

    def attach_trigger_files(run, trigger_data)
      return trigger_data if trigger_files.blank?

      normalized_trigger_files.each_with_object(trigger_data.dup) do |(field_name, files), data|
        blobs = uploaded_files(files).map { |file| create_blob_payload(run, file) }
        next if blobs.empty?

        data[field_name.to_s] = blobs.one? ? blobs.first : blobs
      end
    end

    def normalized_trigger_files
      return trigger_files.to_unsafe_h if trigger_files.respond_to?(:to_unsafe_h)
      return trigger_files.to_h if trigger_files.respond_to?(:to_h)

      trigger_files
    end

    def uploaded_files(files)
      Array(files).grep(ActionDispatch::Http::UploadedFile)
    end

    def create_blob_payload(run, file)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: file.original_filename,
        content_type: file.content_type,
      )
      run.files.attach(blob)

      {
        filename: blob.filename.to_s,
        url: blob_url_resolver.call(blob),
        blob_id: blob.id,
      }
    end
  end
end
