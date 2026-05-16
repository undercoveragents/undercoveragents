# frozen_string_literal: true

# Helper for building flow_data structures in mission specs.
# Usage:
#   flow = MissionFlowBuilder.build do |f|
#     f.node("t1", type: "input", label: "Start")
#     f.node("n1", type: "llm", label: "LLM", prompt: "Say hello")
#     f.node("o1", type: "output", label: "Done")
#     f.edge("t1", "n1")
#     f.edge("n1", "o1")
#   end
module MissionFlowBuilder
  class Builder
    def initialize
      @nodes = []
      @edges = []
    end

    def node(id, type:, label: nil, **data)
      node_hash = {
        "id" => id.to_s,
        "type" => type.to_s,
        "position" => { "x" => @nodes.size * 200, "y" => 100 },
        "data" => {
          "label" => label || type.to_s.titleize,
          "icon" => "fa-solid fa-circle",
          "color" => "#6366f1",
        }.merge(data.transform_keys(&:to_s)),
      }
      @nodes << node_hash
      self
    end

    def edge(source, target, id: nil, source_handle: nil, target_handle: nil)
      edge = {
        "id" => id || "e-#{source}-#{target}",
        "source" => source.to_s,
        "target" => target.to_s,
      }
      edge["sourceHandle"] = source_handle.to_s if source_handle
      edge["targetHandle"] = target_handle.to_s if target_handle
      @edges << edge
      self
    end

    def build
      { "nodes" => @nodes, "edges" => @edges }
    end
  end

  def self.build(&)
    builder = Builder.new
    yield builder
    builder.build
  end
end
