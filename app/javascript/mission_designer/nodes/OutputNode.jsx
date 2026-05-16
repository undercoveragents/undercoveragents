import React, { memo } from "react";
import { Handle, Position } from "@xyflow/react";
import NodeWrapper from "./NodeWrapper";

function formatOutputPreview(value, maxLength = 180) {
  if (value == null || value === "") return null;

  let rendered;

  if (typeof value === "string") {
    rendered = value;
  } else {
    try {
      rendered = JSON.stringify(value);
    } catch {
      rendered = String(value);
    }
  }

  const compact = rendered.replace(/\s+/g, " ").trim();
  if (!compact) return null;
  if (compact.length <= maxLength) return compact;

  return `${compact.slice(0, maxLength - 3)}...`;
}

function normalizeSelectedVariables(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => formatOutputPreview(item, 80))
      .filter(Boolean);
  }

  if (value && typeof value === "object") {
    return Object.keys(value);
  }

  const formatted = formatOutputPreview(value, 80);
  return formatted ? [formatted] : [];
}

export default memo(function OutputNode({ data, selected }) {
  const selectedVars = normalizeSelectedVariables(data.selected_variables);
  const status = data.status || "success";
  const statusCode = data.status_code;
  const responseBody = formatOutputPreview(data.response_body);

  return (
    <NodeWrapper data={data} selected={selected} type="output">
      <Handle
        type="target"
        position={Position.Left}
        className="ms-handle ms-handle-target"
      />
      <div className="ms-node-extras">
        <div className={`ms-node-tag ${status === "error" ? "ms-node-tag-error" : ""}`}>
          <i className={`fa-solid ${status === "error" ? "fa-circle-xmark" : "fa-circle-check"}`}></i>
          {status}{statusCode ? ` (${statusCode})` : ""}
        </div>
        {responseBody && (
          <div className="ms-node-tag ms-node-tag-full">
            <i className="fa-solid fa-reply"></i>
            <span className="ms-node-tag-text">{responseBody}</span>
          </div>
        )}
        {selectedVars.length > 0 && selectedVars.map((v, index) => (
          <div className="ms-node-tag" key={`${v}-${index}`}>
            <i className="fa-solid fa-arrow-right"></i>
            {v}
          </div>
        ))}
        {selectedVars.length === 0 && !responseBody && (
          <div className="ms-node-tag ms-node-tag-muted">
            <i className="fa-solid fa-circle-info"></i>
            All upstream variables
          </div>
        )}
      </div>
    </NodeWrapper>
  );
});
