# frozen_string_literal: true

module Admin
  class ToolsController < BaseController
    include ModelOptionsSupport
    include Toggleable

    before_action :set_tool, only: [
      :show,
      :edit,
      :edit_instructions,
      :update,
      :destroy,
      :toggle,
      :edit_widget,
      :update_widget,
      :discover_schema,
      :edit_visibility,
      :update_visibility,
    ]

    def index
      authorize Tool
      @tools = scoped_tools.ordered
      @builtin_tools = current_operation.headquarter? ? BuiltinTools::Registry.visible_definitions : []
    end

    def show = authorize(@tool)

    def new
      authorize Tool
      @tool_types = ToolPlugin.all_types.sort_by { |type| type.fetch(:label) }
      @tool_type = params[:type]
    end

    def edit
      authorize @tool
      @tool_type = @tool.toolable.class.type_key
      @toolable = @tool.toolable
    end

    def edit_instructions
      authorize @tool, :update?
      ensure_instruction_editor_available!
      load_instruction_form_data
    end

    def edit_widget
      authorize @tool, :update?
      @toolable = @tool.toolable
    end

    def create
      build_new_tool!
      authorize @tool

      if @tool.save
        flash_options = { notice: t("tools.created") }
        discovery_result = auto_discover_tool(@tool)
        flash_options[:alert] = discovery_result.message if discovery_result&.success? == false

        redirect_to admin_tool_path(@tool), **flash_options
      else
        @tool_type = params[:tool_type]
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @tool
      @toolable = @tool.toolable
      tool_attributes = update_tool_params

      Tool.transaction do
        @toolable.update!(@toolable.class.permitted_params(params))
        @tool.update!(tool_attributes) if tool_attributes.present?
      end

      redirect_to admin_tool_path(@tool), notice: t("tools.updated")
    rescue ActiveRecord::RecordInvalid
      render_failed_update
    end

    def update_widget
      authorize @tool, :update?
      @toolable = @tool.toolable

      @toolable.update!(@toolable.class.permitted_params(params))
      redirect_to admin_tool_path(@tool), notice: t("tools.widget_updated")
    rescue ActiveRecord::RecordInvalid
      render :edit_widget, status: :unprocessable_content
    end

    def destroy
      authorize @tool

      @tool.destroy!
      redirect_to admin_tools_path, notice: t("tools.deleted"), status: :see_other
    end

    def toggle = super
    def toggle_record = @tool
    def toggle_redirect_path = admin_tools_path
    def toggle_i18n_prefix = "tools"

    def discover_schema
      authorize @tool, :discover_schema?
      result = @tool.toolable.perform_discovery!
      tool_path = admin_tool_path(@tool)

      if result.success?
        redirect_to tool_path, notice: result.message
      else
        redirect_to tool_path, alert: result.message
      end
    end

    def edit_visibility
      authorize @tool, :edit_visibility?
      return if @tool.toolable.visibility_available?

      redirect_to admin_tool_path(@tool),
                  alert: t("tools.schema_discovery_required")
    end

    def update_visibility
      authorize @tool, :update_visibility?

      @tool.toolable.update_visibility!(params)
      redirect_to admin_tool_path(@tool),
                  notice: t("tools.visibility_updated")
    end

    private

    def set_tool = @tool = scoped_tools.friendly.find(params.expect(:id))

    def build_new_tool!
      toolable_class = ToolPlugin.resolve(params[:tool_type])
      raise ActionController::BadRequest, "Unknown tool type" unless toolable_class

      @toolable = toolable_class.build_from_params(params)
      @tool = Tool.new(create_tool_params.merge(tool_type: params[:tool_type], operation: current_operation))
      @tool.configurator = @toolable
    end

    def load_instruction_form_data
      @toolable = @tool.toolable
      @available_llm_connectors = scoped_connectors.llm_providers.enabled.ordered
    end

    def render_failed_update
      @toolable = @tool.toolable

      case params.dig(:tool, :edit_context)
      when "instructions"
        load_instruction_form_data
        render :edit_instructions, status: :unprocessable_content
      else
        @tool_type = @tool.toolable.class.type_key
        render :edit, status: :unprocessable_content
      end
    end

    def ensure_instruction_editor_available!
      return if instruction_editor_available?(@tool.toolable)

      raise ActiveRecord::RecordNotFound, "This tool does not support instruction editing"
    end

    def instruction_editor_available?(toolable)
      return toolable.instructions_editable? if toolable.respond_to?(:instructions_editable?)

      toolable.respond_to?(:instructions)
    end

    def auto_discover_tool(tool)
      toolable = tool.toolable
      return unless toolable.respond_to?(:auto_discover_after_create?) && toolable.auto_discover_after_create?

      toolable.perform_discovery!
    end

    def create_tool_params
      params.expect(tool: [:name, :description, :enabled])
    end

    def update_tool_params
      params.fetch(:tool, ActionController::Parameters.new).permit(:name, :description, :enabled)
    end
  end
end
