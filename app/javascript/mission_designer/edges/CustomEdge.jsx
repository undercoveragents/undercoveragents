import React from "react";
import { BaseEdge, getSmoothStepPath, EdgeLabelRenderer } from "@xyflow/react";

export default function CustomEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  style = {},
  markerEnd,
  data,
  selected,
  animated,
}) {
  const edgeStyle = style || {};
  const [edgePath, labelX, labelY] = getSmoothStepPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
    borderRadius: 12,
  });

  return (
    <>
      <BaseEdge
        path={edgePath}
        markerEnd={markerEnd}
        style={{
          stroke: selected ? "#6366f1" : "#94a3b8",
          strokeWidth: selected ? 2.5 : 1.5,
          ...edgeStyle,
          ...(animated ? { strokeDasharray: 5, animation: "ms-dash 0.6s linear infinite" } : {}),
        }}
        className={animated ? "ms-edge-animated" : ""}
      />
      {data?.label && (
        <EdgeLabelRenderer>
          <div
            className="ms-edge-label"
            style={{
              transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
            }}
          >
            {data.label}
          </div>
        </EdgeLabelRenderer>
      )}
    </>
  );
}
