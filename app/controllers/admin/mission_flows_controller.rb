# frozen_string_literal: true

module Admin
  class MissionFlowsController < BaseController
    include MissionRecordContext
    include ModelOptionsSupport

    before_action :set_mission
    before_action :authorize_mission_show!, only: [
      :flow_data_json,
      :node_model_options,
      :node_image_model_options,
      :mission_io_fields,
      :node_properties,
    ]
    before_action :authorize_mission_update!, only: [:save_flow, :duplicate_node, :delete_node, :undo_flow, :redo_flow]

    def flow_data_json
      render json: flow_response(@mission)
    end

    def save_flow
      old_flow = @mission.flow_data.deep_dup
      if @mission.update(flow_data: normalized_flow_param(params.dig(:mission, :flow_data)))
        @mission.push_undo_snapshot!(old_flow) if old_flow != @mission.flow_data
        respond_to do |format|
          format.html { redirect_to admin_missions_path, notice: t("missions.saved") }
          format.json do
            render json: { saved: true, **flow_response(@mission) }
          end
        end
      else
        respond_to do |format|
          format.html { render "admin/missions/designer", status: :unprocessable_content }
          format.json do
            render json: { saved: false, errors: @mission.errors.full_messages },
                   status: :unprocessable_content
          end
        end
      end
    end

    def node_model_options
      @models = models_for_connector(params[:connector_id])
      @selected_model = params[:selected_model_id]
      render template: "admin/missions/node_model_options"
    end

    def node_image_model_options
      @models = models_for_connector(params[:connector_id], filter: :image)
      @selected_model = params[:selected_model_id]
      render template: "admin/missions/node_model_options"
    end

    def mission_io_fields
      sub_mission = @mission.operation.missions.find_by(id: params[:sub_mission_id])
      return render(json: { input_fields: [], output_fields: [] }) unless sub_mission

      render json: {
        input_fields: sub_mission.input_field_definitions,
        output_fields: sub_mission.output_field_definitions,
      }
    end

    def node_properties
      @presenter = NodePropertiesPresenter.new(mission: @mission, node_id: params[:node_id])
      return head(:not_found) unless @presenter.found?

      @llm_connectors = scoped_connectors.llm_providers.enabled.ordered
      render template: "admin/missions/node_properties"
    end

    def duplicate_node
      node_id = params[:node_id]
      flow = normalized_flow_param(params[:flow_data])
      source = flow["nodes"].find { |node| node["id"] == node_id }
      return render json: { error: "Node not found" }, status: :not_found unless source

      if singleton_node?(source["type"], flow)
        return render json: { error: "Only one #{source["type"]} node is allowed" }, status: :unprocessable_content
      end

      @mission.push_undo_snapshot!(flow.dup)
      flow["nodes"] << build_duplicate_node(source)
      @mission.update!(flow_data: flow)
      render json: flow_response(@mission)
    end

    def delete_node
      node_id = params[:node_id]
      flow = normalized_flow_param(params[:flow_data])
      @mission.push_undo_snapshot!(flow.dup)
      flow["nodes"].reject! { |node| node["id"] == node_id }
      flow["edges"].reject! { |edge| edge["source"] == node_id || edge["target"] == node_id }
      @mission.update!(flow_data: flow)
      render json: flow_response(@mission)
    end

    def undo_flow
      undo_stack = @mission.flow_undo_history || []
      return render json: empty_history_response if undo_stack.empty?

      snapshot = undo_stack.last
      new_undo = undo_stack[0..-2]
      new_redo = ((@mission.flow_redo_history || []) + [@mission.flow_data]).last(Missions::FlowHistory::HISTORY_LIMIT)
      @mission.update_columns( # rubocop:disable Rails/SkipsModelValidations
        flow_data: snapshot,
        flow_undo_history: new_undo,
        flow_redo_history: new_redo,
      )
      render json: history_response(snapshot, can_undo: new_undo.any?, can_redo: true)
    end

    def redo_flow
      redo_stack = @mission.flow_redo_history || []
      return render json: empty_history_response if redo_stack.empty?

      snapshot = redo_stack.last
      new_redo = redo_stack[0..-2]
      new_undo = ((@mission.flow_undo_history || []) + [@mission.flow_data]).last(Missions::FlowHistory::HISTORY_LIMIT)
      @mission.update_columns( # rubocop:disable Rails/SkipsModelValidations
        flow_data: snapshot,
        flow_undo_history: new_undo,
        flow_redo_history: new_redo,
      )
      render json: history_response(snapshot, can_undo: true, can_redo: new_redo.any?)
    end

    private

    def authorize_mission_show! = authorize @mission, :show?

    def authorize_mission_update! = authorize @mission, :update?

    def normalized_flow_param(value)
      Missions::FlowPersistenceNormalizer.parse_and_normalize(value, tenant: @mission.operation.tenant)
    end

    def empty_history_response
      history_response(@mission.flow_data, can_undo: @mission.can_undo?, can_redo: @mission.can_redo?)
    end

    def history_response(flow, can_undo:, can_redo:)
      {
        nodes: flow["nodes"] || [],
        edges: normalized_flow_edges(flow),
        global_variables: flow["global_variables"] || [],
        can_undo:,
        can_redo:,
        node_errors: Missions::NodeConfigValidator.validate_flow(flow),
      }
    end

    def build_duplicate_node(source)
      source.deep_dup.merge(
        "id" => "node-#{SecureRandom.hex(6)}",
        "position" => {
          "x" => (source.dig("position", "x") || 0).to_f + 32,
          "y" => (source.dig("position", "y") || 0).to_f + 32,
        },
      )
    end

    def flow_response(mission)
      history_response(mission.flow_data, can_undo: mission.can_undo?, can_redo: mission.can_redo?)
    end

    def normalized_flow_edges(flow) = Missions::FlowEdgeNormalizer.normalize_all(flow["edges"])

    def singleton_node?(type, flow)
      meta = MissionNodePlugin.metadata_for(type)
      meta&.dig(:singleton) == true &&
        flow["nodes"].any? { |node| node["type"] == type }
    end
  end
end
