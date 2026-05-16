import React, { memo } from "react";
import { Handle, Position } from "@xyflow/react";
import NodeWrapper from "./NodeWrapper";

export default memo(function SwitchNode({ data, selected }) {
  const cases = data.cases || {};
  const caseEntries = Object.entries(cases);

  return (
    <NodeWrapper data={data} selected={selected} type="switch">
      <Handle
        type="target"
        position={Position.Left}
        className="ms-handle ms-handle-target"
      />
      {data.expression && (
        <div className="ms-node-tag ms-node-tag-full">
          <i className="fa-solid fa-code"></i>
          <span className="ms-node-tag-text">{data.expression}</span>
        </div>
      )}
      <div className="ms-node-ports">
        {caseEntries.map(([port, value]) => (
          <div className="ms-port-item" key={port}>
            <span className="ms-port-dot ms-port-dot-case"></span>
            <span className="ms-port-label">{value}</span>
            <Handle
              type="source"
              position={Position.Right}
              id={port}
              className="ms-handle ms-handle-source"
            />
          </div>
        ))}
        <div className="ms-port-item">
          <span className="ms-port-dot ms-port-dot-default"></span>
          <span className="ms-port-label">Default</span>
          <Handle
            type="source"
            position={Position.Right}
            id="default"
            className="ms-handle ms-handle-source"
          />
        </div>
      </div>
    </NodeWrapper>
  );
});
