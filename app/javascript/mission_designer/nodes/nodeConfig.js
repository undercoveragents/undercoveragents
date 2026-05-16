// Declarative configuration for all mission designer node types.
// DataDrivenNode reads this config to render the appropriate handles, tags, and ports.
// Only nodes with truly unique rendering (SwitchNode, InputNode, OutputNode) remain as
// dedicated components.

const DEFAULT_ITERATOR_PARALLEL_BRANCHES = 5;

function iteratorParallelTag(data) {
  if (`${data.parallel}` !== "true") return null;

  const rawMaxParallelBranches = Number.parseInt(data.max_parallel_branches, 10);
  const maxParallelBranches = Number.isFinite(rawMaxParallelBranches) && rawMaxParallelBranches > 0
    ? rawMaxParallelBranches
    : DEFAULT_ITERATOR_PARALLEL_BRANCHES;

  return `Parallel x${maxParallelBranches}`;
}

const NODE_CONFIGS = {
  // ── Simple passthrough ──
  capability: {},
  trigger: { hasTarget: false },

  // ── Single full-width tag ──
  code: {
    tags: [{ field: "code", icon: "fa-solid fa-terminal", fullWidth: true }],
  },

  text_template: {
    tags: [{ field: "template", icon: "fa-solid fa-file-lines", fullWidth: true }],
  },

  unique: {
    tags: [{ field: "field", fullWidth: true, prefix: "by " }],
  },

  // ── Tag list ──
  mission: {
    tags: [{ field: "mission_name", icon: "fa-solid fa-diagram-project" }],
  },

  tool: {
    tags: [{ field: "toolType", icon: "fa-solid fa-tag", transform: (v) => v.replace(/_/g, " ") }],
  },

  delay: {
    tags: [{ render: (d) => d.duration ? `${d.duration} ${d.unit || "seconds"}` : null, icon: "fa-solid fa-hourglass-half" }],
  },

  limit: {
    tags: [
      { render: (d) => d.count ? `Take ${d.count}` : null, icon: "fa-solid fa-scissors" },
      { render: (d) => d.offset && Number(d.offset) > 0 ? `Skip ${d.offset}` : null },
    ],
  },

  sort: {
    tags: [
      { render: (d) => d.direction ? (d.direction === "desc" ? "Descending" : "Ascending") : null,
        iconFn: (d) => `fa-solid fa-arrow-${d.direction === "desc" ? "down" : "up"}-a-z` },
      { field: "field", fullWidth: true, prefix: "by " },
    ],
  },

  aggregate: {
    tags: [
      { field: "operation", icon: "fa-solid fa-calculator" },
      { field: "collection", fullWidth: true },
    ],
  },

  // ── Complex tag lists ──
  llm: {
    tags: [
      { field: "connector_name", icon: "fa-solid fa-plug" },
      { fields: ["model_name", "model"], icon: "fa-solid fa-microchip" },
      { field: "temperature", icon: "fa-solid fa-temperature-half", condition: (d) => d.temperature !== undefined },
      { field: "prompt", icon: "fa-solid fa-message", fullWidth: true },
    ],
  },

  agent: {
    tags: [
      { field: "agent_name", icon: "fa-solid fa-user-secret" },
      { field: "model", icon: "fa-solid fa-microchip" },
      { field: "temperature", icon: "fa-solid fa-temperature-half", condition: (d) => d.temperature !== undefined },
      { field: "prompt", icon: "fa-solid fa-message", fullWidth: true },
    ],
  },

  generate_image: {
    tags: [
      { field: "connector_name", icon: "fa-solid fa-plug" },
      { fields: ["model_name", "model"], icon: "fa-solid fa-microchip" },
      { field: "size", icon: "fa-solid fa-expand", condition: (d) => d.size },
      { field: "prompt", icon: "fa-solid fa-message", fullWidth: true },
    ],
  },

  // ── Dynamic tags from object keys ──
  set_variable: {
    renderExtras: (data) => {
      const names = Object.keys(data.assignments || {});
      if (names.length === 0) return null;
      return names.map((name) => ({ text: name, icon: "fa-solid fa-equals", key: name }));
    },
  },

  json_extract: {
    tags: [{ field: "source", icon: "fa-solid fa-file-code", fullWidth: true }],
    renderExtras: (data) => {
      const entries = Object.entries(data.extractions || {});
      if (entries.length === 0) return null;
      return entries.map(([name, path]) => ({ text: `${name}: ${path}`, icon: "fa-solid fa-arrow-right", key: name }));
    },
  },

  // ── Multi-port (ms-node-ports) ──
  condition: {
    tags: [{ field: "expression", icon: "fa-solid fa-code", fullWidth: true }],
  },

  iterator: {
    tags: [
      { render: iteratorParallelTag, icon: "fa-solid fa-shuffle" },
      { field: "collection", icon: "fa-solid fa-list", fullWidth: true },
    ],
  },

  loop: {
    tags: [
      { field: "condition", icon: "fa-solid fa-code" },
      { field: "max_iterations", icon: "fa-solid fa-hashtag", prefix: "max " },
    ],
  },

  // ── Positioned ports ──
  filter: {
    tags: [{ field: "expression", icon: "fa-solid fa-filter", fullWidth: true }],
  },

  http_request: {
    tags: [
      { field: "method", icon: "fa-solid fa-arrow-right" },
      { render: (d) => d.auth_type && d.auth_type !== "none" ? d.auth_type.replace(/_/g, " ") : null,
        icon: "fa-solid fa-key" },
      { render: (d) => d.body_mode && d.body_mode !== "none" ? d.body_mode.replace(/_/g, " ") : null,
        icon: "fa-solid fa-box-open" },
      { field: "url", icon: "fa-solid fa-link", fullWidth: true },
    ],
  },

  write_file: {
    tags: [
      { field: "filename", icon: "fa-solid fa-file", fullWidth: true },
    ],
  },
};

export default NODE_CONFIGS;
