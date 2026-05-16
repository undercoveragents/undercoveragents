# frozen_string_literal: true

module Admin
  module Rag
    class RunsController < BaseController
      before_action :set_rag_flow
      before_action :set_run, only: [:show, :cancel]

      def index
        @runs = @rag_flow.rag_runs.ordered
      end

      def show
        @run.recover_if_stale!

        return unless request.format.turbo_stream? && params[:format] == "turbo_stream"

        render turbo_stream: turbo_stream.replace(
          "rag-run-#{@run.id}",
          partial: "rag/runs/run_detail",
          locals: { run: @run },
        )
      end

      def cancel
        unless @run.cancel!
          redirect_to admin_rag_flow_run_path(@rag_flow, @run),
                      alert: t("rag_runs.cannot_cancel", default: "Only running or pending runs can be cancelled.")
          return
        end

        redirect_to admin_rag_flow_run_path(@rag_flow, @run),
                    notice: t("rag_runs.cancelled", default: "Run cancelled.")
      end

      private

      def set_rag_flow
        @rag_flow = scoped_rag_flows.friendly.find(params.expect(:rag_flow_id))
      end

      def set_run
        @run = @rag_flow.rag_runs.find(params.expect(:id))
      end
    end
  end
end
