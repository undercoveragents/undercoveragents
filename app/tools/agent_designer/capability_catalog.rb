# frozen_string_literal: true

module AgentDesigner
  class CapabilityCatalog
    class << self
      def render
        types = CapabilityPlugin.all_types.sort_by { |type| type[:label].to_s }
        return "No capabilities available." if types.empty?

        lines = ["## Capabilities (use these keys with `manage_capability`)"]
        types.each do |type|
          capability_class = CapabilityPlugin.resolve(type[:key])
          lines << "- `#{type[:key]}` — #{type[:label]} — #{type[:description]}"
          capability_fields(capability_class).each do |field|
            lines << "  - #{capability_field_summary(field)}"
          end
          capability_notes(capability_class).each do |note|
            lines << "  - Note: #{note}"
          end
        end
        lines.join("\n")
      end

      private

      def capability_fields(capability_class)
        return [] unless capability_class.respond_to?(:agent_designer_fields)

        Array(capability_class.agent_designer_fields)
      end

      def capability_notes(capability_class)
        return [] unless capability_class.respond_to?(:agent_designer_notes)

        Array(capability_class.agent_designer_notes)
      end

      def capability_field_summary(field)
        parts = ["`#{field[:name]}` (#{field[:type]})"]
        parts << "default=`#{field[:default]}`" unless field[:default].nil?
        parts << "allowed=#{Array(field[:allowed_values]).join(", ")}" if field[:allowed_values].present?
        parts << "required when #{field[:required_when]}" if field[:required_when].present?
        parts << field[:description].to_s if field[:description].present?
        parts.join(" — ")
      end
    end
  end
end
