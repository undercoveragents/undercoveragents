import React, { forwardRef, useState, useEffect } from "react";
import { useNodeId } from "@xyflow/react";

const STATUS_CONFIG = {
  running:   { iconCls: "fa-circle-notch fa-spin", label: "Running"   },
  success:   { iconCls: "fa-circle-check",         label: "Done"      },
  failure:   { iconCls: "fa-circle-xmark",          label: "Failed"    },
  disabled:  { iconCls: "fa-ban",                   label: "Disabled"  },
  skip:      { iconCls: "fa-forward",               label: "Skipped"   },
  cancelled: { iconCls: "fa-ban",                   label: "Cancelled" },
};

const SINGLETON_TYPES = (() => {
  try {
    const el = document.getElementById("mission-designer-root");
    return el ? JSON.parse(el.dataset.singletonTypes || "[]") : [];
  } catch {
    return [];
  }
})();

const NodeWrapper = forwardRef(function NodeWrapper({ data, selected, type, children }, ref) {
  const nodeId = useNodeId();
  const [menuOpen, setMenuOpen] = useState(false);
  const accentColor = data.color || "#6366f1";
  const debugState = data._debugState;
  const hasConfigError = data._hasConfigError;
  const configErrorTooltip = data._configErrorTooltip || "Configuration errors present";
  const isDisabled = !!data.disabled || debugState === "disabled";
  const completedCount = data._debugCompletedCount || 0;
  const statusCfg = debugState ? STATUS_CONFIG[debugState] : null;
  const showIterationCount =
    (debugState === "running" && completedCount > 0) || completedCount > 1;

  const menuRef = React.useRef(null);

  // Close menu when node is deselected (e.g. user clicks canvas or another node)
  useEffect(() => {
    if (!selected) setMenuOpen(false);
  }, [selected]);

  // Close menu when clicking outside (needed for non-selected nodes where the selected
  // prop doesn't change)
  useEffect(() => {
    if (!menuOpen) return;
    const handleClickOutside = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setMenuOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside, true);
    return () => document.removeEventListener("mousedown", handleClickOutside, true);
  }, [menuOpen]);

  const handleToggleMenu = (e) => {
    // Stop propagation so clicking the menu doesn't select the node
    e.stopPropagation();
    setMenuOpen((prev) => !prev);
  };

  const handleMenuAction = (e, action) => {
    e.stopPropagation();
    setMenuOpen(false);
    const canvas = e.currentTarget.closest(".ms-canvas");
    if (!canvas || !nodeId) return;
    canvas.dispatchEvent(new CustomEvent("ms:node-action", { detail: { nodeId, action } }));
  };

  return (
    <div
      ref={ref}
      className={[
        "ms-node",
        `ms-node-${type}`,
        selected ? "ms-node-selected" : "",
        debugState ? `ms-exec-${debugState}` : "",
        isDisabled ? "ms-node-disabled" : "",
      ].filter(Boolean).join(" ")}
      style={{ "--node-accent": accentColor }}
    >
      {statusCfg && (
        <div className={`ms-node-status-indicator ms-node-status-${debugState}`}>
          <i className={`fa-solid ${statusCfg.iconCls}`} />
          {showIterationCount && (
            <span className="ms-node-iteration-count">&times;{completedCount}</span>
          )}
          {data._debugDuration != null && (
            <span className="ms-node-status-duration">
              {data._debugDuration >= 1000
                ? `${(data._debugDuration / 1000).toFixed(1)}s`
                : `${data._debugDuration}ms`}
            </span>
          )}
        </div>
      )}
      {hasConfigError && !debugState && (
        <div className="ms-node-error-badge" title={configErrorTooltip}>
          <i className="fa-solid fa-triangle-exclamation"></i>
        </div>
      )}
      <div className="ms-node-menu nodrag nowheel" ref={menuRef}>
        <button
          className="ms-node-menu-trigger"
          type="button"
          onClick={handleToggleMenu}
          onMouseDown={(e) => e.stopPropagation()}
          title="Node actions"
        >
          <i className="fa-solid fa-ellipsis-vertical" />
        </button>
        {menuOpen && (
          <ul className="ms-node-menu-dropdown">
            {!SINGLETON_TYPES.includes(type) && (
              <li>
                <button
                  className="ms-node-menu-item"
                  type="button"
                  onClick={(e) => handleMenuAction(e, "duplicate")}
                >
                  <i className="fa-regular fa-copy" />
                  Duplicate
                </button>
              </li>
            )}
            {!SINGLETON_TYPES.includes(type) && (
              <li>
                <button
                  className="ms-node-menu-item"
                  type="button"
                  onClick={(e) => handleMenuAction(e, isDisabled ? "enable" : "disable")}
                >
                  <i className={isDisabled ? "fa-solid fa-toggle-on" : "fa-solid fa-toggle-off"} />
                  {isDisabled ? "Enable" : "Disable"}
                </button>
              </li>
            )}
            <li>
              <button
                className="ms-node-menu-item ms-node-menu-item-danger"
                type="button"
                onClick={(e) => handleMenuAction(e, "delete")}
              >
                <i className="fa-solid fa-trash-can" />
                Delete
              </button>
            </li>
          </ul>
        )}
      </div>
      <div className="ms-node-content">
        <div className="ms-node-header">
          <div className="ms-node-icon-wrap">
            <i className={data.icon || "fa-solid fa-circle"} style={{ color: accentColor }}></i>
          </div>
          <div className="ms-node-label">{data.label}</div>
        </div>
        {data.description && (
          <div className="ms-node-description">{data.description}</div>
        )}
        {debugState === "failure" && data._debugError && (
          <div className="ms-node-exec-error">
            <i className="fa-solid fa-triangle-exclamation"></i>
            <span>{data._debugError}</span>
          </div>
        )}
        {children}
      </div>
    </div>
  );
});

export default NodeWrapper;
