# frozen_string_literal: true

module Admin
  module MissionControl
    class RunsController < BaseController
      before_action :set_run, only: [:show, :timeline]

      # Flow snapshot stays deferred to the timeline action; the show page still needs execution_state for summary stats.
      LIGHT_COLUMNS = [
        :id, :status, :mission_id, :api_client_id, :current_node_id,
        :started_at, :completed_at, :created_at, :updated_at,
        :error, :callback_url, :trigger_data, :variables, :execution_state,
      ].freeze

      def index
        base_scope = tenant_scoped_mission_runs
        base_scope = filter_by_operation(base_scope)
        @q = base_scope.ransack(permitted_q_params)
        @pagy, @runs = pagy(:offset, @q.result.includes(mission: :operation).recent, limit: 50)
        @filter_options = build_filter_options
      end

      def show
        @execution_stats = compute_execution_stats(@run.node_executions)
        @agent_chats = find_agent_chats
      end

      def timeline
        @node_executions = @run.node_executions
        @flow_nodes = build_flow_nodes_map
        @execution_stats = compute_execution_stats(@node_executions)
        render partial: "timeline", locals: {
          run: @run,
          node_executions: @node_executions,
          flow_nodes: @flow_nodes,
          execution_stats: @execution_stats,
        }
      end

      private

      def set_run
        scope = params[:action] == "show" ? light_scope : timeline_scope
        @run = scope.find(params.expect(:id))
      end

      def light_scope
        tenant_scoped_mission_runs.select(*LIGHT_COLUMNS).includes(:mission, :api_client)
      end

      def timeline_scope
        tenant_scoped_mission_runs
      end

      def permitted_q_params
        return {} if params[:q].blank?

        params.expect(q: [:id_eq, :status_eq, :mission_id_eq, :s])
      end

      def build_filter_options
        {
          statuses: ::MissionRun.statuses.keys,
          missions: scoped_missions.ordered.pluck(:name, :id),
          operations: scoped_operations.ordered.pluck(:name, :slug),
        }
      end

      def filter_by_operation(scope)
        return scope if params[:operation].blank?

        op = scoped_operations.friendly.find(params.expect(:operation))
        scope.where(mission_id: Mission.where(operation: op).select(:id))
      end

      def build_flow_nodes_map
        nodes = @run.flow_snapshot["nodes"] || []
        nodes.index_by { |n| n["id"] }
      end

      def compute_execution_stats(executions)
        total_duration = executions.sum do |e|
          next 0 unless e.started_at && e.finished_at

          (e.finished_at - e.started_at) * 1000
        end

        {
          total_nodes: executions.size,
          successful: executions.count { |e| e.status == :success },
          failed: executions.count { |e| e.status == :failure },
          skipped: executions.count { |e| e.status == :skip },
          total_duration_ms: total_duration,
        }
      end

      def find_agent_chats
        return [] unless @run.started_at

        time_range = @run.started_at..(@run.completed_at || Time.current)
        tenant_scoped_chats.where(execution_context: :mission, mission_id: @run.mission_id, created_at: time_range)
                           .includes(:agent, :model)
                           .order(created_at: :asc)
      end
    end
  end
end
