// Shared node type metadata helpers.
// The Rails view injects a JSON map into `#mission-designer-root[data-node-type-metadata]`
// describing each registered mission node type (icon, color, ports, singleton, etc.).
// These helpers parse that payload once and cache it for subsequent lookups.

let cache = null;

function readCache() {
  if (cache) return cache;
  try {
    const el = document.getElementById("mission-designer-root");
    cache = el ? JSON.parse(el.dataset.nodeTypeMetadata || "{}") : {};
  } catch {
    cache = {};
  }
  return cache;
}

/** Returns the full metadata map keyed by node type. */
export function getAllNodeTypeMetadata() {
  return readCache();
}

/** Returns metadata for a single node type, or null if unknown. */
export function getNodeTypeMetadata(type) {
  const all = readCache();
  return all[type] || null;
}

/** Reset the cache — exposed for tests. */
export function resetNodeTypeMetadataCache() {
  cache = null;
}
