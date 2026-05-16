import React, { memo } from "react";
import { Handle, Position } from "@xyflow/react";
import NodeWrapper from "./NodeWrapper";

const TYPE_ICONS = {
  string: "fa-solid fa-font",
  string_array: "fa-solid fa-list",
  number: "fa-solid fa-hashtag",
  number_array: "fa-solid fa-list-ol",
  boolean: "fa-solid fa-toggle-on",
  boolean_array: "fa-solid fa-list-check",
  file: "fa-solid fa-file",
  file_array: "fa-solid fa-files",
  json: "fa-solid fa-code",
  date: "fa-solid fa-calendar",
  date_array: "fa-solid fa-calendar-days",
  datetime: "fa-solid fa-clock",
  datetime_array: "fa-solid fa-clocks",
};

export default memo(function InputNode({ data, selected }) {
  const fields = data.fields || [];

  return (
    <NodeWrapper data={data} selected={selected} type="input">
      {fields.length > 0 && (
        <div className="ms-node-extras">
          {fields.map((field, i) => (
            <div className="ms-node-tag" key={field.variable_name || i}>
              <i className={TYPE_ICONS[field.field_type] || "fa-solid fa-circle"}></i>
              {field.variable_name || "unnamed"}
              {field.required && <span className="ms-node-tag-required">*</span>}
            </div>
          ))}
        </div>
      )}
      {fields.length === 0 && (
        <div className="ms-node-extras">
          <div className="ms-node-tag ms-node-tag-muted">
            <i className="fa-solid fa-circle-info"></i>
            No fields defined
          </div>
        </div>
      )}
      <Handle
        type="source"
        position={Position.Right}
        id="default"
        className="ms-handle ms-handle-source"
      />
    </NodeWrapper>
  );
});
