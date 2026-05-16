# frozen_string_literal: true

module Api
  module V1
    class ChannelInvocationsController < Api::ChannelBaseController
      before_action :set_channel_target
      before_action :set_invocation, only: [:show]

      def show
        if mission_target?
          render json: serialize_mission_run(@invocation)
        else
          render json: serialize_agent_chat(@invocation)
        end
      end

      def create
        if mission_target?
          run = mission_invoker.call(
            payload: validated_payload,
            callback_url: params[:callback_url],
            file_params: params,
          )

          render json: serialize_mission_run(run), status: :accepted
        else
          result = agent_invoker.call(
            content: params.expect(:content).to_s,
            response_mode: current_channel.response_mode,
          )

          render json: serialize_agent_invocation(result), status: agent_response_status(result)
        end
      rescue Channels::MissionInvoker::InvalidInvocation, Channels::AgentInvoker::InvalidInvocation => e
        render_unprocessable(e.message)
      end

      private

      def set_channel_target
        @channel_target = current_channel.channel_targets.find_by!(slug: params.expect(:target_slug))
      rescue ActiveRecord::RecordNotFound
        render_not_found("Channel target not found")
      end

      def set_invocation
        scope = mission_target? ? @channel_target.mission_runs : @channel_target.chats
        @invocation = scope.find_by(id: params[:id], channel_id: current_channel.id)
        render_not_found("Invocation not found") unless @invocation
      end

      def mission_target?
        @channel_target.target_type == "Mission"
      end

      def mission_invoker
        @mission_invoker ||= Channels::MissionInvoker.new(channel: current_channel, channel_target: @channel_target)
      end

      def agent_invoker
        @agent_invoker ||= Channels::AgentInvoker.new(channel: current_channel, channel_target: @channel_target)
      end

      def validated_payload
        payload = @channel_target.target.filter_trigger_data(extract_payload)
        missing = @channel_target.target.validate_required_inputs(payload_with_files(payload))

        if missing.any?
          raise Channels::MissionInvoker::InvalidInvocation, "Missing required fields: #{missing.join(", ")}"
        end

        payload
      end

      def extract_payload
        raw = params[:payload]
        return {} if raw.blank?
        return JSON.parse(raw) if raw.is_a?(String)

        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      rescue JSON::ParserError
        {}
      end

      def payload_with_files(payload)
        file_names = @channel_target.target.file_field_names
        merged = payload.dup
        file_names.each { |name| merged[name] = true if file_param?(name) }
        merged
      end

      def file_param?(name)
        file = params[name]
        return true if file.is_a?(ActionDispatch::Http::UploadedFile)
        return file.any?(ActionDispatch::Http::UploadedFile) if file.is_a?(Array)

        false
      end

      def serialize_mission_run(run)
        result = {
          invocation_id: run.id,
          invocation_type: "mission_run",
          status: run.status,
          channel: { slug: current_channel.slug, name: current_channel.name },
          target: serialize_target,
          started_at: run.started_at&.iso8601,
          completed_at: run.completed_at&.iso8601,
          duration: run.duration&.round(2),
        }

        if run.completed?
          result[:result] = extract_mission_result(run)
        elsif run.failed?
          result[:error] = run.error
        end

        result
      end

      def extract_mission_result(run)
        variables = run.variables || {}
        output_meta = variables["_output_meta"]

        {
          output: variables.except("_trigger_data", "_current_node_data", "_nesting_depth", "_output_meta"),
          meta: output_meta,
        }
      end

      def serialize_agent_invocation(result)
        base = serialize_agent_chat(result.chat)
        return base unless result.sync?

        base.merge(result: { content: result.response_content })
      end

      def serialize_agent_chat(chat)
        {
          invocation_id: chat.id,
          invocation_type: "chat",
          status: chat.status,
          channel: { slug: current_channel.slug, name: current_channel.name },
          target: serialize_target,
          title: chat.display_title,
          messages: serialized_messages(chat),
        }
      end

      def serialized_messages(chat)
        chat.messages.where(role: [:user, :assistant]).order(:id).map do |message|
          {
            id: message.id,
            role: message.role,
            content: message.content.to_s,
            created_at: message.created_at.iso8601,
          }
        end
      end

      def serialize_target
        {
          slug: @channel_target.slug,
          name: @channel_target.name,
          kind: @channel_target.target_kind,
        }
      end

      def agent_response_status(result)
        result.sync? ? :ok : :accepted
      end
    end
  end
end
