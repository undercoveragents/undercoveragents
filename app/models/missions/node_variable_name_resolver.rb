# frozen_string_literal: true

module Missions
  module NodeVariableNameResolver
    module_function

    def build_map(flow_data)
      used = {}

      Array(flow_data&.dig("nodes")).grep(Hash).each_with_object({}) do |node, map|
        node_id = node["id"].to_s
        base = base_name(node["data"], node_id)
        next if base.blank?

        map[node_id] = reserve_unique_name(base, used)
      end
    end

    def for_node(node_id, flow_data)
      build_map(flow_data)[node_id.to_s]
    end

    def assign!(flow_data)
      names = build_map(flow_data)

      Array(flow_data&.dig("nodes")).grep(Hash).each do |node|
        data = node["data"]
        next unless data.is_a?(Hash)

        resolved = names[node["id"].to_s]
        resolved.present? ? data["name"] = resolved : data.delete("name")
      end

      flow_data
    end

    def base_name(node_data, node_id)
      data = node_data.is_a?(Hash) ? node_data : {}
      sanitize(data["name"].presence || data["label"].presence || node_id)
    end

    def sanitize(raw)
      raw.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "").presence
    end

    def reserve_unique_name(base, used)
      candidate = base
      suffix = 2

      while used[candidate]
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end

      used[candidate] = true
      candidate
    end
    private_class_method :reserve_unique_name
  end
end
