import React, { memo } from "react";
import { Handle, Position } from "@xyflow/react";
import NodeWrapper from "./NodeWrapper";
import NODE_CONFIGS from "./nodeConfig";
import { getNodeTypeMetadata } from "../utils/nodeMetadata";

// Derive CSS dot class from port key for visual styling
const PORT_DOT_MAP = {
  true: "ms-port-dot-true",
  false: "ms-port-dot-false",
  loop: "ms-port-dot-loop",
  done: "ms-port-dot-done",
  match: "ms-port-dot-true",
  no_match: "ms-port-dot-false",
  success: "ms-port-dot-true",
  error: "ms-port-dot-false",
};

/** Resolve ports: prefer server metadata, enrich with visual dot classes */
function resolvePorts(type) {
  const metadata = getNodeTypeMetadata(type);
  const serverPorts = metadata?.output_ports;
  if (!serverPorts || serverPorts.length <= 1) return null;
  return serverPorts.map((p) => ({
    ...p,
    dotClass: PORT_DOT_MAP[p.key] || "",
  }));
}

/**
 * Data-driven node component that renders based on declarative configuration.
 * Replaces 22 individual node components with a single component + config map.
 * Only SwitchNode, InputNode, and OutputNode remain as dedicated components.
 */
function DataDrivenNode({ data, selected, type }) {
  const config = NODE_CONFIGS[type] || {};
  const hasTarget = config.hasTarget !== false;
  const hasSource = config.hasSource !== false;
  const tags = config.tags || [];
  const ports = resolvePorts(type);

  // Resolve tags into renderable items
  const resolvedTags = resolveTags(tags, data);
  const extraTags = config.renderExtras ? config.renderExtras(data) : null;

  // Separate full-width tags from inline tags
  const inlineTags = resolvedTags.filter((t) => !t.fullWidth);
  const fullWidthTags = resolvedTags.filter((t) => t.fullWidth);

  return (
    <NodeWrapper data={data} selected={selected} type={type}>
      {hasTarget && (
        <Handle type="target" position={Position.Left} className="ms-handle ms-handle-target" />
      )}

      {/* Inline tags */}
      {(inlineTags.length > 0 || extraTags) && (
        <div className="ms-node-extras">
          {inlineTags.map((tag, i) => (
            <div className="ms-node-tag" key={tag.key || i}>
              {tag.icon && <i className={tag.icon}></i>}
              {tag.text}
            </div>
          ))}
          {extraTags && extraTags.map((tag, i) => (
            <div className="ms-node-tag" key={tag.key || `extra-${i}`}>
              {tag.icon && <i className={tag.icon}></i>}
              {tag.text}
            </div>
          ))}
        </div>
      )}

      {/* Full-width tags */}
      {fullWidthTags.map((tag, i) => (
        <div className="ms-node-tag ms-node-tag-full" key={tag.key || `fw-${i}`}>
          {tag.icon && <i className={tag.icon}></i>}
          <span className="ms-node-tag-text">{tag.text}</span>
        </div>
      ))}

      {/* Standard source handle (single default) */}
      {hasSource && !ports && (
        <Handle type="source" position={Position.Right} id="default" className="ms-handle ms-handle-source" />
      )}

      {/* Multi-port rendering (condition, iterator, loop, filter, http_request) */}
      {ports && (
        <div className="ms-node-ports">
          {ports.map((port) => (
            <div className="ms-port-item" key={port.key}>
              <span className={`ms-port-dot ${port.dotClass || ""}`}></span>
              <span className="ms-port-label">{port.label}</span>
              <Handle type="source" position={Position.Right} id={port.key} className="ms-handle ms-handle-source" />
            </div>
          ))}
        </div>
      )}
    </NodeWrapper>
  );
}

/**
 * Resolve tag configs into renderable tag objects { text, icon, fullWidth, key }.
 */
function resolveTags(tags, data) {
  const result = [];
  for (const tag of tags) {
    // Custom condition check
    if (tag.condition && !tag.condition(data)) continue;

    let text = null;
    let icon = tag.icon;

    if (tag.render) {
      // Custom render function
      text = tag.render(data);
    } else if (tag.fields) {
      // First non-empty field wins
      for (const f of tag.fields) {
        if (data[f]) { text = data[f]; break; }
      }
    } else if (tag.field) {
      text = data[tag.field];
    }

    if (text == null || text === "") continue;

    // Apply transform
    if (tag.transform) text = tag.transform(text);
    // Apply prefix
    if (tag.prefix) text = `${tag.prefix}${text}`;
    // Dynamic icon function
    if (tag.iconFn) icon = tag.iconFn(data);

    result.push({ text, icon, fullWidth: !!tag.fullWidth, key: tag.field || tag.fields?.[0] || text });
  }
  return result;
}

export default memo(DataDrivenNode);
