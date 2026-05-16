import React, { memo } from "react";
import { Handle, Position } from "@xyflow/react";
import NodeWrapper from "./NodeWrapper";
import { getNodeTypeMetadata } from "../utils/nodeMetadata";

/**
 * Generic fallback node for plugin-defined node types that don't have
 * a dedicated React component. Renders handles based on output_ports
 * from the backend MissionNodePlugin metadata.
 */
function GenericNode({ data, selected, type }) {
  const metadata = getNodeTypeMetadata(type);
  const outputPorts = data.output_ports || metadata?.output_ports || [{ key: "default", label: "Output" }];
  const hasInput = data._has_input !== false; // Default to true

  return (
    <NodeWrapper data={data} selected={selected} type={type}>
      {hasInput && (
        <Handle
          type="target"
          position={Position.Left}
          className="ms-handle ms-handle-target"
        />
      )}
      {data.expression && (
        <div className="ms-node-tag ms-node-tag-full">
          <i className="fa-solid fa-code"></i>
          <span className="ms-node-tag-text">{data.expression}</span>
        </div>
      )}
      {outputPorts.length === 1 && (
        <Handle
          type="source"
          position={Position.Right}
          id={outputPorts[0].key}
          className="ms-handle ms-handle-source"
        />
      )}
      {outputPorts.length > 1 && (
        <div className="ms-node-ports">
          {outputPorts.map((port) => (
            <div className="ms-port-item" key={port.key}>
              <span className="ms-port-dot"></span>
              <span className="ms-port-label">{port.label}</span>
              <Handle
                type="source"
                position={Position.Right}
                id={port.key}
                className="ms-handle ms-handle-source"
              />
            </div>
          ))}
        </div>
      )}
    </NodeWrapper>
  );
}

export default memo(GenericNode);
