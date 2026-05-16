# frozen_string_literal: true

module Admin
  class RagFlowsController < BaseController
    include Toggleable

    before_action :set_rag_flow, only: [:show, :edit, :update, :destroy, :toggle, :execute]

    def index
      authorize RagFlow
      @rag_flows = scoped_rag_flows.ordered
    end

    def show
      authorize @rag_flow
    end

    def new
      @rag_flow = RagFlow.new
      authorize @rag_flow
    end

    def edit
      authorize @rag_flow
    end

    def create
      @rag_flow = RagFlow.new(rag_flow_params.merge(operation: current_operation))
      authorize @rag_flow

      if @rag_flow.save
        redirect_to admin_rag_flow_path(@rag_flow),
                    notice: t("rag_flows.created", default: "RAG created successfully.")
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @rag_flow

      if @rag_flow.update(rag_flow_params)
        redirect_to admin_rag_flow_path(@rag_flow),
                    notice: t("rag_flows.updated", default: "RAG updated successfully.")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @rag_flow
      @rag_flow.destroy!
      redirect_to admin_rag_flows_path,
                  notice: t("rag_flows.deleted", default: "RAG deleted."),
                  status: :see_other
    end

    def toggle = super
    def toggle_record = @rag_flow
    def toggle_redirect_path = admin_rag_flow_path(@rag_flow)
    def toggle_i18n_prefix = "rag_flows"

    def execute
      authorize @rag_flow

      # :nocov:
      unless @rag_flow.runnable?
        redirect_to admin_rag_flow_path(@rag_flow),
                    alert: t("rag_flows.not_runnable",
                             default: "Flow must be enabled to run.",),
                    status: :see_other
        return
      end
      # :nocov:

      # Create the run record synchronously so it is visible on the show page
      # immediately after redirect, before the async job picks it up.
      run = @rag_flow.rag_runs.create!(status: :pending, triggered_by: "manual", stats: {})
      ::Rag::ExecutionJob.perform_later(
        @rag_flow.id,
        tenant_id: @rag_flow.operation.tenant_id,
        triggered_by: "manual",
        run_id: run.id,
      )
      redirect_to admin_rag_flow_run_path(@rag_flow, run),
                  notice: t("rag_flows.execution_started", default: "RAG execution started."),
                  status: :see_other
    end

    private

    def set_rag_flow
      @rag_flow = scoped_rag_flows.friendly.find(params.expect(:id))
    end

    def rag_flow_params
      params.expect(rag_flow: [:name])
    end
  end
end
