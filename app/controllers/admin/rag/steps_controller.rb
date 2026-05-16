# frozen_string_literal: true

module Admin
  module Rag
    class StepsController < BaseController
      before_action :set_rag_flow
      before_action :set_stage, only: [:edit, :update, :destroy]

      def edit
        authorize @rag_flow, :update?
        @existing_step = @rag_flow.rag_steps.find_by(stage: @stage)

        if @existing_step || params[:module_type].present?
          load_module_data
          render :edit
        else
          @available_modules = RagStepPlugin.modules_for_stage(@stage)
          render :select_module
        end
      end

      def update
        authorize @rag_flow, :update?

        module_type_key = params[:module_type]
        klass = RagStepPlugin.resolve(module_type_key)
        raise ActiveRecord::RecordNotFound, "Unknown module: #{module_type_key}" unless klass

        validate_module_stage!(module_type_key)

        existing_step = @rag_flow.rag_steps.find_by(stage: @stage)

        if existing_step && existing_step.module_type == module_type_key
          update_existing_step(existing_step, klass, module_type_key)
        else
          create_new_step(existing_step, klass, module_type_key)
        end
      end

      def destroy
        authorize @rag_flow, :update?

        step = @rag_flow.rag_steps.find_by(stage: @stage)
        step&.destroy!

        redirect_to edit_admin_rag_flow_step_path(@rag_flow, @stage),
                    notice: t("rag_steps.removed", default: "Module removed. Choose a new one."),
                    status: :see_other
      end

      private

      def validate_module_stage!(module_type_key)
        return if RagStepPlugin.stage_for(module_type_key).to_s == @stage

        raise ActiveRecord::RecordNotFound, "Module '#{module_type_key}' is not valid for stage '#{@stage}'"
      end

      def update_existing_step(existing_step, klass, module_type_key)
        configurator = klass.new(klass.permitted_params(params))
        if configurator.valid?
          existing_step.update!(configuration: configurator.to_configuration)
          redirect_to flow_path, notice: t("rag_steps.updated", default: "Step updated successfully.")
        else
          load_module_data(selected_key: module_type_key, steppable_override: configurator)
          render :edit, status: :unprocessable_content
        end
      end

      def create_new_step(existing_step, klass, module_type_key)
        configurator = klass.new(klass.permitted_params(params))
        if configurator.valid?
          ActiveRecord::Base.transaction do
            existing_step&.destroy!
            @rag_flow.rag_steps.create!(
              stage: @stage,
              module_type: module_type_key,
              configuration: configurator.to_configuration,
            )
          end
          redirect_to flow_path, notice: t("rag_steps.configured", default: "Step configured successfully.")
        else
          load_module_data(selected_key: module_type_key, steppable_override: configurator)
          render :edit, status: :unprocessable_content
        end
      end

      def set_rag_flow
        @rag_flow = scoped_rag_flows.friendly.find(params.expect(:rag_flow_id))
      end

      def set_stage
        @stage = params[:stage]
        @stage_config = RagFlow.stage_config(@stage)
        raise ActiveRecord::RecordNotFound, "Unknown stage: #{@stage}" unless @stage_config
      end

      def load_module_data(selected_key: nil, steppable_override: nil)
        existing_step = @rag_flow.rag_steps.find_by(stage: @stage)

        @selected_module_key = resolve_selected_module_key(selected_key, existing_step)

        klass = resolve_selected_module_class(@selected_module_key)
        @selected_module = build_selected_module(klass)
        @steppable = resolve_steppable(existing_step, klass, steppable_override)
      end

      def resolve_selected_module_key(selected_key, existing_step)
        selected_key || existing_step&.module_type || params[:module_type]
      end

      def resolve_selected_module_class(module_key)
        RagStepPlugin.resolve(module_key) || raise(ActiveRecord::RecordNotFound, "Unknown module: #{module_key}")
      end

      def build_selected_module(klass)
        {
          key: @selected_module_key,
          label: klass.label,
          icon: klass.icon,
          description: klass.description,
        }
      end

      def resolve_steppable(existing_step, klass, steppable_override)
        return steppable_override if steppable_override
        return build_preview_steppable(klass) if preview_params_for?(@selected_module_key)
        return existing_step.configurator if existing_step&.module_type == @selected_module_key

        klass.new
      end

      def preview_params_for?(module_key)
        request.get? && params[module_key].present?
      end

      def build_preview_steppable(klass)
        klass.build_from_params(params)
      end

      def flow_path
        admin_rag_flow_path(@rag_flow)
      end
    end
  end
end
