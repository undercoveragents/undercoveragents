# frozen_string_literal: true

module Missions
  class FlowEdgeNormalizer
    CUSTOM_EDGE_TYPE = "custom"
    DEFAULT_MARKER_TYPE = "arrowclosed"

    class << self
      def normalize(edge)
        cleaned = edge.except("selected")
        cleaned["type"] = CUSTOM_EDGE_TYPE if cleaned["type"].blank?
        cleaned["markerEnd"] = normalize_marker_end(cleaned["markerEnd"])

        data = cleaned["data"].is_a?(Hash) ? cleaned["data"].deep_dup : {}
        label = edge_label_for(cleaned)

        if label.present?
          data["label"] = label
        else
          data.delete("label")
        end

        if data.present?
          cleaned["data"] = data
        else
          cleaned.delete("data")
        end

        cleaned
      end

      def normalize_all(edges)
        Array(edges).map { |edge| normalize(edge) }
      end

      private

      def normalize_marker_end(marker_end)
        marker = marker_end.is_a?(Hash) ? marker_end.deep_dup : {}
        marker["type"] = DEFAULT_MARKER_TYPE if marker["type"].blank?
        marker
      end

      def edge_label_for(edge)
        source_handle = edge["sourceHandle"].presence || "default"
        return if source_handle == "default"

        source_handle
      end
    end
  end
end
