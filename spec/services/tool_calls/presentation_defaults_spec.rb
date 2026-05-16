# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolCalls::PresentationDefaults do
  describe ".resolve_user_tool" do
    let(:display_name) { "Orders Explorer" }
    let(:icon) { "fa-solid fa-database" }

    def configured_toolable
      Class.new do
        def self.tool_widget_default_presentation(display_name:, icon:)
          ToolCalls::Presentation.new(
            display_name:,
            icon:,
            running_messages: ["Default running"],
            complete_messages: ["Default complete"],
          )
        end

        def tool_widget_override_presentation(display_name:, **)
          ToolCalls::Presentation.new(
            display_name:,
            icon: "fa-solid fa-bolt",
            running_mode: "rotate",
          )
        end
      end.new
    end

    def raising_toolable
      Class.new do
        def self.tool_widget_default_presentation(display_name:, icon:)
          ToolCalls::Presentation.new(
            display_name:,
            icon:,
            running_messages: ["Default running"],
          )
        end

        def tool_widget_override_presentation(*)
          raise StandardError, "boom"
        end
      end.new
    end

    def resolve_user_tool(toolable)
      described_class.resolve_user_tool(
        tool_type: "sql_query",
        display_name:,
        icon:,
        toolable:,
        toolable_class: toolable.class,
      )
    end

    it "merges tool widget overrides into the shared defaults" do
      presentation = resolve_user_tool(configured_toolable)

      expect(presentation).to have_attributes(
        display_name:,
        icon: "fa-solid fa-bolt",
        running_mode: "rotate",
        running_messages: ["Default running"],
        complete_messages: ["Default complete"],
      )
    end

    it "falls back to the shared defaults when override resolution raises" do
      presentation = resolve_user_tool(raising_toolable)

      expect(presentation).to have_attributes(
        display_name:,
        icon:,
        running_messages: ["Default running"],
      )
    end
  end

  describe ".for_user_tool" do
    it "builds a fallback presentation when the tool type cannot be resolved" do
      presentation = described_class.for_user_tool(
        tool_type: "missing_tool_type",
        display_name: "Demo Tool",
        icon: "fa-solid fa-bolt",
      )

      expect(presentation).to have_attributes(
        display_name: "Demo Tool",
        icon: "fa-solid fa-bolt",
      )
    end

    it "falls back when the tool class default presentation raises" do
      stub_const("BrokenPresentationTool", Class.new do
        def self.tool_widget_default_presentation(**)
          raise "boom"
        end
      end,)

      presentation = described_class.for_user_tool(
        tool_type: "broken_presentation_tool",
        display_name: "Broken Tool",
        icon: "fa-solid fa-triangle-exclamation",
        toolable_class: BrokenPresentationTool,
      )

      expect(presentation).to have_attributes(
        display_name: "Broken Tool",
        icon: "fa-solid fa-triangle-exclamation",
      )
    end
  end

  describe ".for_subagent" do
    it "uses the subagent name as the canonical display label" do
      presentation = described_class.for_subagent(name: "Mission Designer")

      expect(presentation).to have_attributes(
        display_name: "Mission Designer",
        icon: "fa-solid fa-robot",
      )
      expect(presentation.running_messages).to include("Handing the task to Mission Designer…")
    end
  end
end
