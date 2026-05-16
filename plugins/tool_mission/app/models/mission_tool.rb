# frozen_string_literal: true

# JSONB-backed ActiveModel configurator for Mission tools.
# Data lives in `tools.configuration` JSONB column — no separate table.
#
# When attached to an agent, this tool executes the referenced mission,
# mapping the mission's input fields to tool parameters and returning
# the mission's output.
module Tools
  class MissionTool
    include UndercoverAgents::PluginSystem::Configurator
    include ToolWidgetConfigurable
    include ToolPlugin

    attr_accessor :_tool_record

    attribute :mission_id, :integer
    attribute :instructions, :string

    validates :mission_id, presence: true
    validates :instructions, length: { maximum: 10_000 }
    validate :mission_must_exist

    # ── Tool Type Protocol ────────────────────────────────────────

    def self.type_key = "mission_tool"
    def self.type_label = "Mission"
    def self.type_icon = "fa-solid fa-diagram-project"

    def self.tool_widget_default_presentation(display_name:, icon:)
      ToolCalls::Presentation.new(
        display_name:,
        icon:,
        running_messages: [
          "Starting the mission workflow…",
          "Passing inputs into the mission…",
          "Waiting for downstream mission steps…",
        ],
        complete_messages: [
          "Mission run completed.",
          "Workflow output collected.",
          "Mission results are ready.",
        ],
      )
    end

    def self.tool_designer_editable_attributes
      [
        "mission_id",
        "instructions",
        *ToolWidgetConfigurable::DESIGNER_ATTRIBUTE_KEYS,
      ]
    end

    def self.tool_designer_notes
      [
        "Use list_resources(kind: \"missions\") to resolve mission_id values.",
        "The selected mission controls the runtime input and output shape for this tool.",
      ]
    end

    def self.tool_designer_field_hints
      {
        "mission_id" => resource_hint("missions"),
      }
    end

    def self.runtime_tool_adapter_class_name = "MissionToolAdapter"

    def self.tool_runtime_name_prefix = "mission"

    def self.permitted_params(params)
      permit_params_with_widget(params, [:mission_id, :instructions])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def reset_configurator_caches
      @mission_cache = nil
    end

    # ── Mission accessor ──────────────────────────────────────────

    def mission
      return @mission_cache if defined?(@mission_cache) && @mission_cache&.id == mission_id

      @mission_cache = mission_id.present? ? ::Mission.find_by(id: mission_id) : nil
    end

    def mission=(record)
      @mission_cache = record
      self.mission_id = record&.id
    end

    # ── Mission introspection ─────────────────────────────────────

    def input_fields
      mission&.input_fields || []
    end

    def output_variables
      mission&.output_field_names || []
    end

    private

    def mission_must_exist
      return if mission_id.blank?
      return if mission.present?

      errors.add(:mission_id, "must reference an existing mission")
    end
  end
end
