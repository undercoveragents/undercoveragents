import React, { useCallback, useRef, useMemo, useEffect, useState } from "react";
import ELK from "elkjs/lib/elk.bundled.js";
import {
  ReactFlow,
  Controls,
  ControlButton,
  MiniMap,
  Background,
  addEdge,
  useNodesState,
  useEdgesState,
  MarkerType,
  BackgroundVariant,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import InputNode from "./nodes/InputNode";
import SwitchNode from "./nodes/SwitchNode";
import OutputNode from "./nodes/OutputNode";
import DataDrivenNode from "./nodes/DataDrivenNode";
import GenericNode from "./nodes/GenericNode";
import NODE_CONFIGS from "./nodes/nodeConfig";
import CustomEdge from "./edges/CustomEdge";
import CameraManager from "./CameraManager";
import { invalidLoopBodyConnection } from "./utils/edgeContracts";
import { getAllNodeTypeMetadata } from "./utils/nodeMetadata";

// Build node type map: types with config use DataDrivenNode, specialized types keep their own component
const knownNodeTypes = {
  input: InputNode,
  switch: SwitchNode,
  output: OutputNode,
};
// Register all config-driven node types
for (const type of Object.keys(NODE_CONFIGS)) {
  knownNodeTypes[type] = DataDrivenNode;
}

// Proxy-based fallback: unknown node types render with GenericNode
const nodeTypes = new Proxy(knownNodeTypes, {
  get(target, prop) {
    if (typeof prop === "symbol") return target[prop];
    return target[prop] || GenericNode;
  },
});

const edgeTypes = { custom: CustomEdge };

const elk = new ELK();
const MAX_CANVAS_ZOOM = 1.3;
const FIT_VIEW_OPTIONS = { padding: 0.3, maxZoom: MAX_CANVAS_ZOOM };
const DEFAULT_EDGE_COLOR = "#6366f1";
const EXECUTED_EDGE_COLOR = "#16a34a";

/** Read singleton node types from the data attribute injected by the Rails view */
function getSingletonTypes() {
  try {
    const el = document.getElementById("mission-designer-root");
    return el ? JSON.parse(el.dataset.singletonTypes || "[]") : [];
  } catch {
    return [];
  }
}

const ELK_LAYOUT_OPTIONS = {
  "elk.algorithm": "layered",
  "elk.direction": "RIGHT",
  "elk.layered.spacing.nodeNodeBetweenLayers": "80",
  "elk.spacing.nodeNode": "50",
  "elk.layered.nodePlacement.strategy": "BRANDES_KOEPF",
  "elk.layered.considerModelOrder.strategy": "NODES_AND_EDGES",
};

/**
 * Build ELK port definitions for a node based on its type metadata and data.
 * Every node gets a WEST input port and one or more EAST output ports.
 * Port order is preserved via FIXED_ORDER so ELK places targets vertically
 * aligned with the correct source handle — preventing edge crossings.
 * Returns { ports, portIds } where portIds is a Set of declared port IDs.
 */
function buildElkPorts(node) {
  const ports = [];
  const portIds = new Set();

  // Input port (target handle) — trigger nodes have no input
  const config = NODE_CONFIGS[node.type];
  const hasTarget = !config || config.hasTarget !== false;
  // InputNode (type === "input") also has no target handle
  if (hasTarget && node.type !== "input") {
    const id = `${node.id}__target`;
    ports.push({ id, layoutOptions: { "elk.port.side": "WEST" } });
    portIds.add(id);
  }

  // Output ports (source handles) — resolve from node data or metadata
  let outputKeys = ["default"];
  if (node.type === "switch") {
    const cases = node.data?.cases || {};
    outputKeys = [...Object.keys(cases), "default"];
  } else {
    const meta = getAllNodeTypeMetadata()[node.type];
    const serverPorts = meta?.output_ports;
    if (serverPorts && serverPorts.length > 0) {
      outputKeys = serverPorts.map((p) => p.key);
    }
  }

  for (let i = 0; i < outputKeys.length; i++) {
    const id = `${node.id}__${outputKeys[i]}`;
    ports.push({
      id,
      layoutOptions: {
        "elk.port.side": "EAST",
        "elk.port.index": `${i}`,
      },
    });
    portIds.add(id);
  }

  return { ports, portIds };
}

// Parse the numeric suffix from a node ID like "node-123" → 123, or fall back to 0.
function parseNodeIndex(id) {
  const m = id && id.match(/-(\d+)$/);
  return m ? parseInt(m[1], 10) : 0;
}

// Module-level counter — seeded at first component mount via seedNodeIdCounter().
let nodeIdCounter = 100;
function seedNodeIdCounter(nodes) {
  const max = nodes.reduce((acc, n) => Math.max(acc, parseNodeIndex(n.id)), 99);
  if (max >= nodeIdCounter) nodeIdCounter = max + 1;
}

// Dispatch a custom event on the container element for the Stimulus controller to pick up
function emit(container, name, detail) {
  container.dispatchEvent(new CustomEvent(name, { bubbles: true, detail }));
}

function normalizeNodeForPersistence(node) {
  const {
    selected,
    dragging,
    resizing,
    measured,
    positionAbsolute,
    width,
    height,
    ...persistedNode
  } = node;

  return persistedNode;
}

function normalizeEdgeForPersistence(edge) {
  const {
    selected,
    ...persistedEdge
  } = edge;

  return persistedEdge;
}

function buildMarkerEnd(color) {
  return { type: MarkerType.ArrowClosed, color };
}

export default function MissionDesigner({ initialNodes, initialEdges, flowDataInputId }) {
  // Seed the ID counter before first render so new nodes never collide with existing ones.
  useMemo(() => seedNodeIdCounter(initialNodes), []); // eslint-disable-line react-hooks/exhaustive-deps

  const [nodes, setNodes, onNodesChangeBase] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
  const containerRef = useRef(null);
  const reactFlowInstance = useRef(null);
  const isFirstRender = useRef(true);

  const onNodesChange = useCallback((changes) => {
    onNodesChangeBase(changes);
    if (changes.some((c) => c.type === "remove")) {
      emit(containerRef.current, "ms:node-deselected", {});
    }
  }, [onNodesChangeBase]);
  const skipAutosaveRef = useRef(0);

  // ── Camera follow: track new nodes added by AI and smoothly pan to them ──
  const prevNodeIdsRef = useRef(new Set(initialNodes.map((n) => n.id)));
  const prevEdgeIdsRef = useRef(new Set(initialEdges.map((e) => e.id)));
  const cameraRef = useRef(new CameraManager());

  // Clean up CameraManager on unmount
  useEffect(() => {
    return () => cameraRef.current.destroy();
  }, []);

  // ── Minimap toggle (persisted in localStorage) ──
  const [showMinimap, setShowMinimap] = useState(() => {
    try { return localStorage.getItem("ms-minimap-visible") === "true"; } catch { return false; }
  });

  const toggleMinimap = useCallback(() => {
    setShowMinimap((prev) => {
      const next = !prev;
      try { localStorage.setItem("ms-minimap-visible", String(next)); } catch { /* ignore */ }
      return next;
    });
  }, []);

  // ── Undo/Redo state (driven by Stimulus events) ──
  const [canUndo, setCanUndo] = useState(() => {
    const container = document.getElementById("mission-designer-root");
    return container?.dataset.canUndo === "true";
  });
  const [canRedo, setCanRedo] = useState(() => {
    const container = document.getElementById("mission-designer-root");
    return container?.dataset.canRedo === "true";
  });

  // ── Mode state (driven by Stimulus) ──
  const [mode, setMode] = useState(() => {
    const container = document.getElementById("mission-designer-root");
    return container?.dataset.initialMode || "design";
  });

  // ── Zoom percentage (updated on viewport change) ──
  const [zoomLevel, setZoomLevel] = useState(100);

  // ── Node execution states (driven by Turbo Streams → Stimulus → DOM events) ──
  const [nodeExecutionStates, setNodeExecutionStates] = useState(() => {
    const container = document.getElementById("mission-designer-root");
    try {
      return JSON.parse(container?.dataset.initialNodeStates || "{}");
    } catch { return {}; }
  });

  // ── Edge execution states (driven by Turbo Streams → Stimulus → DOM events) ──
  const [edgeExecutionStates, setEdgeExecutionStates] = useState(() => {
    const container = document.getElementById("mission-designer-root");
    try {
      return JSON.parse(container?.dataset.initialEdgeStates || "{}");
    } catch { return {}; }
  });

  // ── Node validation errors (driven by server responses via Stimulus) ──
  const [nodeErrors, setNodeErrors] = useState(() => {
    const container = document.getElementById("mission-designer-root");
    try {
      return JSON.parse(container?.dataset.nodeErrors || "{}");
    } catch {
      return {};
    }
  });

  const persistedFlowJson = useMemo(
    () => JSON.stringify({
      nodes: nodes.map(normalizeNodeForPersistence),
      edges: edges.map(normalizeEdgeForPersistence),
    }),
    [nodes, edges],
  );

  // ── Sync flow state to hidden form input on every change ──
  useEffect(() => {
    const input = document.getElementById(flowDataInputId);
    if (input) {
      input.value = persistedFlowJson;
    }
  }, [persistedFlowJson, flowDataInputId]);

  // ── Notify Stimulus that flow changed (autosave handled by mission_controller) ──
  useEffect(() => {
    if (isFirstRender.current) {
      isFirstRender.current = false;
      return;
    }
    if (skipAutosaveRef.current > 0) {
      skipAutosaveRef.current -= 1;
      return;
    }
    emit(containerRef.current, "ms:flow-changed", {});
  }, [persistedFlowJson]);

  const onPaneClick = useCallback(() => {
    emit(containerRef.current, "ms:node-deselected", {});
  }, []);

  // ── Connections ──
  const isValidConnection = useCallback((connection) => {
    const allNodes = reactFlowInstance.current?.getNodes() ?? nodes;
    const sourceNode = allNodes.find((n) => n.id === connection.source);
    const targetNode = allNodes.find((n) => n.id === connection.target);
    if (!sourceNode || !targetNode) return false;

    return !invalidLoopBodyConnection(allNodes, edges, connection);
  }, [edges, nodes]);

  const onConnect = useCallback(
    (params) => {
      const allNodes = reactFlowInstance.current?.getNodes() ?? nodes;
      if (invalidLoopBodyConnection(allNodes, edges, params)) return;

      setEdges((eds) =>
        addEdge({
          ...params,
          type: "custom",
          markerEnd: { type: MarkerType.ArrowClosed },
          data: { label: params.sourceHandle && params.sourceHandle !== "default" ? params.sourceHandle : "" },
        }, eds),
      );
    },
    [edges, nodes, setEdges],
  );

  // ── Drop from Rails palette ──
  const onDragOver = useCallback((event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }, []);

  const onDrop = useCallback(
    (event) => {
      event.preventDefault();
      const dataStr = event.dataTransfer.getData("application/reactflow");
      if (!dataStr || !reactFlowInstance.current) return;
      const nodeData = JSON.parse(dataStr);

      // Singleton node types — only one allowed per flow (driven by backend registry)
      const singletonTypes = getSingletonTypes();
      if (singletonTypes.includes(nodeData.type)) {
        const exists = nodes.some((n) => n.type === nodeData.type);
        if (exists) return;
      }

      const position = reactFlowInstance.current.screenToFlowPosition({ x: event.clientX, y: event.clientY });

      const newNode = {
        id: `node-${nodeIdCounter++}`,
        type: nodeData.type,
        position,
        data: nodeData.data,
      };

      setNodes((nds) => nds.concat(newNode));
    },
    [setNodes, nodes],
  );

  // ── Clipboard (copy/paste nodes) ──
  const clipboardRef = useRef([]);

  // ── Listen for commands from Rails (Stimulus) ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;

    const handleUpdate = (e) => {
      const { nodeId, data } = e.detail;
      setNodes((nds) =>
        nds.map((n) => (n.id === nodeId ? { ...n, data: { ...n.data, ...data } } : n)),
      );
    };

    const handleDelete = (e) => {
      const { nodeId } = e.detail;
      setNodes((nds) => nds.filter((n) => n.id !== nodeId));
      setEdges((eds) => eds.filter((e2) => e2.source !== nodeId && e2.target !== nodeId));
      emit(containerRef.current, "ms:node-deselected", {});
    };

    el.addEventListener("ms:update-node", handleUpdate);
    el.addEventListener("ms:delete-node", handleDelete);
    return () => {
      el.removeEventListener("ms:update-node", handleUpdate);
      el.removeEventListener("ms:delete-node", handleDelete);
    };
  }, [setNodes, setEdges]);

  // ── Listen for server-side flow updates (node duplicate/delete via Rails) ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    const handleSetFlow = (e) => {
      if (e.detail.skipAutosave) skipAutosaveRef.current += 1;
      const skipCameraFollow = !!e.detail.skipCameraFollow;
      const preservePositions = !!e.detail.preservePositions;
      const newNodes = e.detail.nodes || [];
      const newEdges = e.detail.edges || [];

      // Detect newly added nodes by comparing with previous set
      const currentIds = prevNodeIdsRef.current;
      const addedNodes = newNodes.filter((n) => !currentIds.has(n.id));

      // Update tracked IDs
      prevNodeIdsRef.current = new Set(newNodes.map((n) => n.id));
      prevEdgeIdsRef.current = new Set(newEdges.map((e) => e.id));

      // Build a lookup of existing React nodes to preserve client-side state.
      // - `measured` is always preserved so React Flow can compute child positions.
      // - When `preservePositions` is set (AI refresh), also keep position/style
      //   from client-side ELK arrange that the server doesn't know about yet.
      const existingNodes = reactFlowInstance.current?.getNodes() ?? [];
      const existingNodeMap = {};
      for (const n of existingNodes) {
        existingNodeMap[n.id] = n;
      }

      const mergedNodes = newNodes.map((n) => {
        const existing = existingNodeMap[n.id];
        if (!existing) {
          // New node — if preservePositions is set, place it to the right of
          // all existing content so it doesn't overlap anything.
          // ELK will reposition it properly when arrange_flow runs.
          if (preservePositions) {
            const maxX = existingNodes.reduce((mx, ex) => {
              const right = (ex.position?.x || 0) + (ex.measured?.width || ex.style?.width || 260);
              return Math.max(mx, right);
            }, 0);
            return { ...n, position: { x: maxX + 80, y: n.position?.y || 0 } };
          }
          return n;
        }
        let merged = existing.measured ? { ...n, measured: existing.measured } : n;
        if (preservePositions) {
          merged = { ...merged, position: existing.position };
          if (existing.style) merged = { ...merged, style: existing.style };
        }
        return merged;
      });

      setNodes(mergedNodes);
      setEdges(newEdges);

      // Only follow genuinely new nodes (not edge endpoints).
      // Edge additions don't change the visual position of existing nodes,
      // so following their endpoints causes unnecessary camera jumps.
      if (addedNodes.length > 0 && !skipCameraFollow) {
        cameraRef.current.followNodes(addedNodes);
      }
    };
    el.addEventListener("ms:set-flow-data", handleSetFlow);
    return () => {
      el.removeEventListener("ms:set-flow-data", handleSetFlow);
    };
  }, [setNodes, setEdges]);

  // ── Listen for validation error updates from Stimulus ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    const handleErrors = (e) => setNodeErrors(e.detail || {});
    el.addEventListener("ms:set-node-errors", handleErrors);
    return () => el.removeEventListener("ms:set-node-errors", handleErrors);
  }, []);

  // ── Select All / Copy / Paste from Stimulus keyboard shortcuts ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;

    const handleSelectAll = () => {
      setNodes((nds) => nds.map((n) => ({ ...n, selected: true })));
      setEdges((eds) => eds.map((e) => ({ ...e, selected: true })));
    };

    const handleCopy = () => {
      const selected = (reactFlowInstance.current?.getNodes() ?? []).filter((n) => n.selected);
      if (selected.length === 0) return;
      clipboardRef.current = selected.map((n) => normalizeNodeForPersistence({ ...n }));
    };

    const handlePaste = () => {
      if (clipboardRef.current.length === 0) return;
      const singletonTypes = getSingletonTypes();
      const existingTypes = new Set((reactFlowInstance.current?.getNodes() ?? []).map((n) => n.type));
      const newNodes = clipboardRef.current
        .filter((n) => !(singletonTypes.includes(n.type) && existingTypes.has(n.type)))
        .map((n) => ({
          ...n,
          id: `node-${nodeIdCounter++}`,
          selected: true,
          position: { x: (n.position?.x || 0) + 50, y: (n.position?.y || 0) + 50 },
        }));
      if (newNodes.length === 0) return;
      // Deselect current nodes, add pasted ones as selected
      setNodes((nds) => [...nds.map((n) => ({ ...n, selected: false })), ...newNodes]);
      // Update clipboard positions for subsequent pastes to cascade
      clipboardRef.current = newNodes.map((n) => normalizeNodeForPersistence({ ...n }));
    };

    el.addEventListener("ms:select-all", handleSelectAll);
    el.addEventListener("ms:copy-nodes", handleCopy);
    el.addEventListener("ms:paste-nodes", handlePaste);
    return () => {
      el.removeEventListener("ms:select-all", handleSelectAll);
      el.removeEventListener("ms:copy-nodes", handleCopy);
      el.removeEventListener("ms:paste-nodes", handlePaste);
    };
  }, [setNodes, setEdges]);

  // ── Auto-arrange: ELK layered layout ──
  const edgesRef = useRef(edges);
  useEffect(() => { edgesRef.current = edges; }, [edges]);

  const autoArrange = useCallback(async () => {
    // Lock camera during arrange — prevents follow from firing mid-transition
    const settleMs = cameraRef.current.lockForArrange();

    const currentNodes = reactFlowInstance.current?.getNodes() ?? nodes;
    const currentEdges = edgesRef.current;
    const elkChildren = [];
    const allPortIds = new Set();

    for (const n of currentNodes) {
      const { ports, portIds } = buildElkPorts(n);
      for (const pid of portIds) allPortIds.add(pid);
      elkChildren.push({
        id: n.id,
        width: n.measured?.width ?? 260,
        height: n.measured?.height ?? 120,
        ports,
        layoutOptions: { "elk.portConstraints": "FIXED_ORDER" },
      });
    }

    const graph = {
      id: "root",
      layoutOptions: ELK_LAYOUT_OPTIONS,
      children: elkChildren,
      edges: currentEdges.map((e) => {
        const srcPort = `${e.source}__${e.sourceHandle || "default"}`;
        const tgtPort = `${e.target}__target`;
        return {
          id: e.id,
          sources: [allPortIds.has(srcPort) ? srcPort : e.source],
          targets: [allPortIds.has(tgtPort) ? tgtPort : e.target],
        };
      }),
    };

    try {
      const layouted = await elk.layout(graph);

      const positionMap = {};
      for (const ln of layouted.children || []) {
        positionMap[ln.id] = { x: ln.x, y: ln.y };
      }

      // Enable smooth transition on nodes before updating positions
      const container = containerRef.current;
      container?.classList.add("arranging");

      setNodes((nds) =>
        nds.map((n) => {
          const pos = positionMap[n.id];
          return pos ? { ...n, position: pos } : n;
        }),
      );

      // Wait for the CSS node transition to complete, THEN check if the
      // camera needs adjusting. This way nodes slide first (user can follow
      // them visually) and the camera only moves if nodes end up off-screen.
      // No disorienting concurrent zoom+slide.
      setTimeout(() => {
        container?.classList.remove("arranging");
        cameraRef.current.settleAfterArrange();
        // Force an immediate save so ELK positions are persisted to the server.
        // Without this, the debounced autosave (800ms) can be overridden by
        // the next AI tool call's save_with_undo!, losing the ELK layout.
        emit(containerRef.current, "ms:request-save", {});
      }, settleMs);
    } catch (err) {
      // layout error — unlock camera
      console.error("ELK layout error:", err);
      cameraRef.current.unlock();
    }
  }, [nodes, setNodes]);

  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    el.addEventListener("ms:auto-arrange", autoArrange);
    return () => el.removeEventListener("ms:auto-arrange", autoArrange);
  }, [autoArrange]);

  // ── Mode toggle listener from Stimulus ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    const handleModeChange = (e) => {
      const newMode = e.detail?.mode || "design";
      setMode(newMode);
      if (newMode === "run") {
        setTimeout(() => cameraRef.current.fitAll(), 50);
      }
    };
    el.addEventListener("ms:mode-change", handleModeChange);
    return () => el.removeEventListener("ms:mode-change", handleModeChange);
  }, []);

  // ── Zoom commands from Stimulus toolbar buttons ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    const handleZoom = (e) => {
      cameraRef.current.zoom(e.detail?.action);
    };
    el.addEventListener("ms:zoom", handleZoom);
    return () => el.removeEventListener("ms:zoom", handleZoom);
  }, []);

  // ── Undo/Redo state updates from Stimulus ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    const handleUndoRedoState = (e) => {
      setCanUndo(!!e.detail?.canUndo);
      setCanRedo(!!e.detail?.canRedo);
    };
    el.addEventListener("ms:undo-redo-state", handleUndoRedoState);
    return () => el.removeEventListener("ms:undo-redo-state", handleUndoRedoState);
  }, []);

  // ── Listen for node state updates from Stimulus (Turbo Stream bridge) ──
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;

    const handleNodeState = (e) => {
      const { nodeId, state, nextPort, durationMs, error, nodeType, completedCount } = e.detail;
      setNodeExecutionStates((prev) => ({
        ...prev,
        [nodeId]: {
          status: state,
          next_port: nextPort,
          duration_ms: durationMs,
          error,
          node_type: nodeType,
          completed_count: completedCount || 0,
        },
      }));
    };

    const handleResetDebug = () => {
      setNodeExecutionStates({});
      setEdgeExecutionStates({});
    };

    const handleEdgeState = (e) => {
      const { edgeId, state } = e.detail;
      setEdgeExecutionStates((prev) => ({
        ...prev,
        [edgeId]: { status: state },
      }));
    };

    const handleSelectDebugNode = (e) => {
      const { nodeId } = e.detail;
      const node = nodes.find((n) => n.id === nodeId);
      if (node) {
        cameraRef.current.centerOnNode(node, { zoom: cameraRef.current.maxZoom });
      }
    };

    el.addEventListener("ms:node-state-update", handleNodeState);
    el.addEventListener("ms:edge-state-update", handleEdgeState);
    el.addEventListener("ms:reset-debug", handleResetDebug);
    el.addEventListener("ms:select-debug-node", handleSelectDebugNode);
    return () => {
      el.removeEventListener("ms:node-state-update", handleNodeState);
      el.removeEventListener("ms:edge-state-update", handleEdgeState);
      el.removeEventListener("ms:reset-debug", handleResetDebug);
      el.removeEventListener("ms:select-debug-node", handleSelectDebugNode);
    };
  }, [nodes]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Apply execution overlays + validation errors to nodes ──
  const nodesWithDebug = useMemo(() => {
    return nodes.map((n) => {
      const hasConfigError = !!nodeErrors[n.id];
      const configErrorTooltip = hasConfigError
        ? nodeErrors[n.id].map((error) => `${error.field}: ${error.message}`).join("\n")
        : null;
      const execState = mode === "run" ? nodeExecutionStates[n.id] : null;
      if (!hasConfigError && !execState) return n;

      // Iterator/loop nodes log status=":success" as soon as the collection is
      // resolved (next_port="loop"), but iterations are still running at that
      // point. Treat as "running" until all iterations finish (next_port="done").
      const isIterOrLoop = n.type === "iterator" || n.type === "loop";
      const effectiveStatus = execState && isIterOrLoop &&
        execState.status === "success" && execState.next_port !== "done"
        ? "running"
        : execState?.status;

      return {
        ...n,
        data: {
          ...n.data,
          ...(hasConfigError ? { _hasConfigError: true, _configErrorTooltip: configErrorTooltip } : {}),
          ...(execState ? {
            _debugState: effectiveStatus,
            _debugDuration: execState.duration_ms,
            _debugError: execState.error,
            _debugCompletedCount: execState.completed_count || 0,
          } : {}),
        },
      };
    });
  }, [nodes, mode, nodeExecutionStates, nodeErrors]);

  // ── Debug: Apply execution state to edges ──
  // Edge states are driven entirely by Ruby and rendered as-is.
  const edgesWithDebug = useMemo(() => {
    if (mode !== "run") return edges;
    return edges.map((e) => {
      const edgeState = edgeExecutionStates[e.id];
      if (!edgeState || edgeState.status === "reset") return { ...e, animated: false };

      if (edgeState.status === "in_progress" || edgeState.status === "traversed") {
        return {
          ...e,
          animated: true,
          style: { stroke: EXECUTED_EDGE_COLOR, strokeWidth: 2.5 },
          markerEnd: buildMarkerEnd(EXECUTED_EDGE_COLOR),
        };
      }

      if (edgeState.status === "completed") {
        return {
          ...e,
          animated: false,
          style: { stroke: EXECUTED_EDGE_COLOR, strokeWidth: 2.5 },
          markerEnd: buildMarkerEnd(EXECUTED_EDGE_COLOR),
        };
      }

      if (edgeState.status === "disabled") {
        return {
          ...e,
          animated: false,
          style: { stroke: "#94a3b8", strokeWidth: 1.5, strokeDasharray: "4 4", opacity: 0.55 },
          markerEnd: buildMarkerEnd("#94a3b8"),
        };
      }

      return { ...e, animated: false };
    });
  }, [edges, mode, edgeExecutionStates]);

  // ── Node click ──
  const onNodeClick = useCallback((_event, node) => {
    if (mode === "run") {
      // In run mode, dispatch to Stimulus for inspector panel
      emit(containerRef.current, "ms:debug-node-clicked", { nodeId: node.id, nodeType: node.type });
      emit(containerRef.current, "ms:node-selected", { node });
      return;
    }

    // Emit selection first so the sidebar opens (and resizes the canvas) before centering.
    emit(containerRef.current, "ms:node-selected", { node });

    // Center on the node, waiting for any sidebar resize to complete
    cameraRef.current.centerOnNode(node, {
      waitForResize: true,
      resizeTarget: containerRef.current,
    });
  }, [mode]);

  const defaultEdgeOptions = useMemo(
    () => ({ type: "custom", markerEnd: buildMarkerEnd(DEFAULT_EDGE_COLOR) }),
    [],
  );

  // ── Track viewport changes for zoom indicator ──
  const onMoveEnd = useCallback((_event, viewport) => {
    setZoomLevel(Math.round(viewport.zoom * 100));
  }, []);

  return (
    <div ref={containerRef} className={`ms-canvas-wrapper ${mode === "run" ? "ms-run-mode" : ""}`} style={{ width: "100%", height: "100%" }}>
      <ReactFlow
        nodes={nodesWithDebug}
        edges={edgesWithDebug}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onNodeClick={onNodeClick}
        onPaneClick={onPaneClick}
        onDragOver={onDragOver}
        onDrop={onDrop}
        onInit={(instance) => { reactFlowInstance.current = instance; cameraRef.current.setInstance(instance); }}
        onMoveEnd={onMoveEnd}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        defaultEdgeOptions={defaultEdgeOptions}
        isValidConnection={isValidConnection}
        fitView
        fitViewOptions={FIT_VIEW_OPTIONS}
        connectionLineStyle={{ stroke: "#6366f1", strokeWidth: 2 }}
        connectionLineType="smoothstep"
        snapToGrid
        snapGrid={[16, 16]}
        maxZoom={MAX_CANVAS_ZOOM}
        deleteKeyCode={mode === "design" ? ["Backspace", "Delete"] : []}
        nodesDraggable={mode === "design"}
        nodesConnectable={mode === "design"}
        elementsSelectable={true}
        proOptions={{ hideAttribution: true }}
      >
        <Background variant={BackgroundVariant.Dots} gap={20} size={1} className="ms-background" />
        <Controls className="ms-controls" showInteractive={false}>
          <ControlButton
            onClick={() => emit(containerRef.current, "ms:request-undo", {})}
            title="Undo"
            disabled={!canUndo || mode === "run"}
            className={!canUndo || mode === "run" ? "ms-control-disabled" : ""}
          >
            <i className="fa-solid fa-rotate-left" style={{ fontSize: 12 }} />
          </ControlButton>
          <ControlButton
            onClick={() => emit(containerRef.current, "ms:request-redo", {})}
            title="Redo"
            disabled={!canRedo || mode === "run"}
            className={!canRedo || mode === "run" ? "ms-control-disabled" : ""}
          >
            <i className="fa-solid fa-rotate-right" style={{ fontSize: 12 }} />
          </ControlButton>
          <ControlButton onClick={autoArrange} title="Auto-arrange">
            <i className="fa-solid fa-diagram-project" style={{ fontSize: 12 }} />
          </ControlButton>
          <ControlButton onClick={toggleMinimap} title={showMinimap ? "Hide minimap" : "Show minimap"}>
            <i className={`fa-solid fa-map ${showMinimap ? "ms-control-active" : ""}`} style={{ fontSize: 12 }} />
          </ControlButton>
        </Controls>
        <div className="ms-zoom-indicator" title="Current zoom level">{zoomLevel}%</div>
        {showMinimap && <MiniMap className="ms-minimap" zoomable pannable nodeStrokeWidth={3} />}
        {nodes.length === 0 && mode === "design" && (
          <div className="ms-empty-canvas">
            <div className="ms-empty-canvas-icon">
              <i className="fa-solid fa-diagram-project"></i>
            </div>
            <div className="ms-empty-canvas-title">Start building your mission</div>
            <div className="ms-empty-canvas-hint">
              <button type="button" className="ms-empty-canvas-link" onClick={() => document.dispatchEvent(new CustomEvent("ms:activate-sidebar-tab", { detail: { tab: "components" } }))}>
                <i className="fa-solid fa-shapes"></i>
                <span>Click Components to add nodes</span>
              </button>
            </div>
            <div className="ms-empty-canvas-hint">
              <button type="button" className="ms-empty-canvas-link" onClick={() => document.dispatchEvent(new CustomEvent("ms:activate-sidebar-tab", { detail: { tab: "chat" } }))}>
                <i className="fa-solid fa-comments"></i>
                <span>Or ask the AI agent to build it for you</span>
              </button>
            </div>
          </div>
        )}
      </ReactFlow>
    </div>
  );
}
