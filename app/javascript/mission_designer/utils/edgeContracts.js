const LOOP_CONTROL_TYPES = new Set(["iterator", "loop"]);
const LOOP_PORT = "loop";

function buildAdjacency(edges) {
  const incomingByTarget = new Map();
  const outgoingBySource = new Map();

  edges.forEach((edge) => {
    const source = edge.source;
    const target = edge.target;
    if (!source || !target) return;

    if (!incomingByTarget.has(target)) incomingByTarget.set(target, []);
    if (!outgoingBySource.has(source)) outgoingBySource.set(source, []);
    incomingByTarget.get(target).push(edge);
    outgoingBySource.get(source).push(edge);
  });

  return { incomingByTarget, outgoingBySource };
}

function loopBodyNodeIds(controlId, outgoingBySource) {
  const visited = new Set();
  const queue = (outgoingBySource.get(controlId) || [])
    .filter((edge) => (edge.sourceHandle || "default") === LOOP_PORT)
    .map((edge) => edge.target)
    .filter(Boolean);

  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId || nodeId === controlId || visited.has(nodeId)) continue;

    visited.add(nodeId);
    (outgoingBySource.get(nodeId) || []).forEach((edge) => {
      if (edge.target && edge.target !== controlId && !visited.has(edge.target)) {
        queue.push(edge.target);
      }
    });
  }

  return visited;
}

function insideBodyEdge(controlId, bodyNodeIds, edge) {
  if (!edge?.source) return false;
  if (edge.source === controlId) return (edge.sourceHandle || "default") === LOOP_PORT;
  return bodyNodeIds.has(edge.source);
}

export function invalidLoopBodyConnection(nodes, edges, connection) {
  const source = connection?.source;
  const target = connection?.target;
  if (!source || !target) return null;

  const augmentedEdges = edges.concat({
    id: "__candidate_loop_body_edge__",
    source,
    target,
    sourceHandle: connection.sourceHandle || "default",
  });

  const nodeById = new Map(nodes.map((node) => [node.id, node]));
  const { incomingByTarget, outgoingBySource } = buildAdjacency(augmentedEdges);

  for (const node of nodes) {
    if (!LOOP_CONTROL_TYPES.has(node.type)) continue;

    const bodyNodeIds = loopBodyNodeIds(node.id, outgoingBySource);
    if (bodyNodeIds.size === 0) continue;

    if (target === node.id && bodyNodeIds.has(source)) {
      return "Loop/iterator bodies cannot reconnect back into their own control node.";
    }

    if (!bodyNodeIds.has(target)) continue;

    const incomingEdges = incomingByTarget.get(target) || [];
    const candidateEdge = incomingEdges.find((edge) => edge.id === "__candidate_loop_body_edge__");
    if (!candidateEdge) continue;

    const candidateInside = insideBodyEdge(node.id, bodyNodeIds, candidateEdge);
    const otherEdges = incomingEdges.filter((edge) => edge.id !== "__candidate_loop_body_edge__");
    const otherHasInside = otherEdges.some((edge) => insideBodyEdge(node.id, bodyNodeIds, edge));
    const otherHasOutside = otherEdges.some((edge) => !insideBodyEdge(node.id, bodyNodeIds, edge));

    if ((candidateInside && otherHasOutside) || (!candidateInside && otherHasInside)) {
      return "Nodes inside a loop/iterator body cannot mix body inputs with outside inputs.";
    }
  }

  return null;
}
