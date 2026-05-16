---
name: mission-designer-handbook
description: Use this skill when the mission designer agent needs the full handbook-level guidance for workflow process, patch format, graph semantics, ports, variables, direct authoring, common patterns, and best practices.
---

# Mission Designer Handbook

Use this skill when detailed mission designer guidance is needed beyond the shorter mission manual summaries.

## Section Index

- `workflow` — Workflow Process
- `patch_format` — Apply Flow Patch - JSON Shape
- `graph_semantics` — Graph Semantics and Joins
- `ports` — Edges and Ports
- `variables` — Variables
- `authoring` — Direct Authoring
- `patterns` — Common Patterns
- `best_practices` — Best Practices

## Workflow Process

Preferred loop for an existing mission: use `read_mission_flow` -> `apply_flow_patch` -> read the patch response.
For a brand-new mission, create the mission record and open its designer page immediately, then pass the
returned mission ID to same-turn flow tools.

1. Call `read_mission_flow` (compact) to see current nodes and edges.
2. If you need exact config shape for one or more node types, call `get_node_type_info`
   with `node_type` or `node_types`.
   If the task suggests a narrower dedicated node, inspect that before `code`
   (for example API JSON usually means `http_request` + `json_extract`).
3. For resource IDs (connectors, default models, tools, agents, missions) call
   `list_resources` with `kind` or `kinds`.
4. Build your desired changes as a single JSON patch and send them with `apply_flow_patch`.
5. The patch tool auto-arranges and validates. Treat config errors and structural issues as blocking,
   warnings as actionable, and do not immediately rerun `validate_flow` when the patch already says
   the flow is valid and warning-free.
  If the patch response reports a variable prefix, use that exact prefix after the patch. Do not keep
  using an old `temp_id` as a variable identifier.
  If the patch is already valid, warning-free, and matches the user's stated request, stop. Do not add
  a follow-up patch just to introduce optional convenience fields, override knobs, or speculative
  refinements the user did not ask for.
6. If something is wrong, fetch targeted detail with `read_mission_flow` (`detail='full'` or
   `node_ids='...'`) before sending the next patch.

## Apply Flow Patch - JSON Shape

`apply_flow_patch` expects a JSON string. Supported keys (all optional):

- add_nodes: `[{ temp_id, type, name?, config?, near_node_id? }]`
  * `temp_id` lets you reference the new node from the same patch (for example in `add_edges`). It is not a variable prefix.
  * `near_node_id` places it next to an existing or newly added node.
- update_nodes: `[{ id, name?, config? }]`
  * Reuse the `id` from `read_mission_flow`.
  * `config` is merged into the existing node data; `name` updates the displayed label.
- remove_nodes: `["node-abc", ...]` or `[{ id: "..." }]`
- add_edges: `[{ source, target, source_port? }]`
  * `source` and `target` accept real IDs or `temp_id` values from `add_nodes`.
- remove_edges: `[{ edge_id?, source?, target? }]`
- add_globals / update_globals: `[{ key, value, type: "string"|"number"|"boolean" }]`
- remove_globals: `["key", ...]`

Example: create an Input -> LLM -> Output pipeline in one call.

```json
{
  "add_nodes": [
    { "temp_id": "in", "type": "input" },
    {
      "temp_id": "llm",
      "type": "llm",
      "config": {
        "connector_id": 1,
        "model": "gpt-4o",
        "system_prompt": "Summarize."
      },
      "near_node_id": "in"
    },
    { "temp_id": "out", "type": "output", "near_node_id": "llm" }
  ],
  "add_edges": [
    { "source": "in", "target": "llm" },
    { "source": "llm", "target": "out" }
  ]
}
```

## Graph Semantics and Joins

- Directed graph. Execution starts from `input` or any node with no incoming edge.
- `output` is terminal - no outgoing edges, ends the mission immediately.
- Same-handle fan-out runs concurrently.
- Implicit join: any node with 2+ distinct immediate predecessors waits for each predecessor
  that still has at least one enabled path into it. Multiple edges from the same upstream
  node count as one predecessor.
- Mutually exclusive branching nodes (`condition`, `switch`, `filter`, `http_request`)
  disable all non-selected outgoing edges when they complete. Disabled edges and nodes never
  block a join.
- Iterator and loop bodies are closed per-iteration subgraphs. Do not wire a body node back
  into the iterator or loop node itself, and do not join a body-fed node with non-body inputs.
  Route once-per-run continuations through the control node `done` port.
- An inner iterator or loop `done` port may remain unconnected when that nested control node
  intentionally ends the current body branch and no post-loop continuation is needed there.
- Loop and iterator bodies may end on any leaf node; never use `output` as a loop-body sink.

## Edges and Ports

Edges connect a source node's output port to a target node's input.

- Most nodes have a single `default` output port.
- `condition`: `true`, `false`
- `switch`: dynamic case keys plus `default`
- `iterator`: `loop`, `done`
- `loop`: `loop`, `done`
- `filter`: `match`, `no_match`
- `http_request`: `success`, `error`

Always set `source_port` explicitly when connecting from a branching node. For mutually
exclusive branchers, only one port will remain enabled at runtime.

## Variables

- Templates: `{{node_prefix.variable}}`; globals: `{{variable_name}}`.
- Use `list_node_variables` or expanded `read_mission_flow` for the exact downstream-visible names.
  Never guess `.result`, reuse `temp_id`, or assume the prefix is just the normalized label.
- Duplicate node labels receive numeric suffixes in their prefixes, for example
  `json_extract`, `json_extract_2`, `json_extract_3`.
- `manage_global_variables` or patch `add_globals` is for seeded external inputs or
  reusable constants - never for values the flow computes later.
- If the design already uses globals for API endpoint, credentials, or other operator-provided
  settings, keep that contract. Do not add parallel input overrides such as `endpoint_override`
  unless the user explicitly asked for request-time overrides.
- `set_variable` uses `assignments` as an object map, for example
  `{"assignments":{"final_summary":"'PASS'"}}`. Do not send `variables` arrays or other aliases.
- Mission formulas evaluate scalars only (number, string, boolean). If a variable is an
  array or hash, derive a scalar upstream first - do not wrap it in `{{...}}` or `DIG(...)`.
- Inside formulas, reference variables directly (`generate_html.response`), not `{{generate_html.response}}`.
- String concatenation in formulas: `CONCAT('prefix=', STR(node.value))`, not `+`.
- For full operator and function docs, call `get_expression_reference`.

## Direct Authoring

Mission Designer authors workflow content directly. Do not delegate to helper agents.

- Node selection: prefer the narrowest built-in node before `code`. Use `json_extract`
  for JSON parsing and extraction, `text_template` for string composition when a downstream
  node truly needs rendered text, `set_variable` for scalar formulas or renames, and collection
  nodes for collection transforms.
- `code` is a last resort. Use it only when existing nodes cannot express the logic or
  when the user explicitly wants custom Ruby.
- Code generation: write the Ruby yourself. Keep it sandbox-safe, use exact upstream
  variable names, and keep `config.output_variables` in sync with every downstream-facing
  `set()` call. Apply the result with `apply_flow_patch` (`update_nodes`).
- Prompt writing: write the prompt yourself. Preserve placeholders exactly, include the
  goal, constraints, and expected output shape when the workflow depends on it.
- Expressions: write the formula yourself. Use exact variable names, keep operands scalar,
  and never wrap formula operands in `{{...}}`.

## Common Output Names

- Give newly added nodes stable `name` values whenever a later node will reference their output.
- `temp_id` is only for same-patch wiring. After the patch, follow the reported variable prefix or the
  exact identifiers from `list_node_variables`.
- `http_request` outputs `node_prefix.status`, `node_prefix.body`, and `node_prefix.headers`.
- `json_extract` outputs `node_prefix.parsed` plus each configured extraction key.
- `text_template` outputs `node_prefix.text`; it does not output `.response`.
- `llm` outputs `node_prefix.response`. If you do not name the node, its default prefix is usually
  `generate_text`, not `llm`.
- `output.selected_variables` uses bare identifiers like `generate_html.response`, while
  `output.response_body` wraps template identifiers like `{{generate_html.response}}`.

## Common Patterns

- Pipeline: Input -> LLM -> Output
- Parallel aggregation: Input -> Task A + Task B -> Shared Summary -> Output
- Conditional routing: Input -> Condition -> [true] LLM A -> Output, [false] LLM B -> Output
- Iteration: Input -> Iterator(items) -> [loop] LLM -> [done] Aggregate -> Output
- API flow: Input -> HTTP Request -> [success] JSON Extract -> LLM -> Output
- Prefer JSON Extract over Code when the job is to parse an API response, read nested
  fields, select array items, or pass a nested object downstream.

## Best Practices

- Use descriptive node labels.
- Prefer the narrowest built-in node that solves the task. Reach for `json_extract`
  before `code` when parsing JSON, selecting nested fields, indexing arrays, or passing
  nested objects downstream.
- Configure required fields at creation time, in the same patch.
- For LLM nodes always set `connector_id` and `model` in `config` unless the user overrides.
- Use `list_resources` before inventing IDs - batch kinds when possible and never guess
  connector, tool, agent, or mission IDs.
- Set `tool_ids` only when the step should be allowed to call mission tools.
- Set LLM thinking fields (`thinking_effort`, etc.) only when the selected model supports
  them and the task actually needs deeper reasoning, not for simple rewrites.
- Use `custom_llm_params` only for explicit provider-specific settings, as a JSON object.
- `aggregate count` returns collection length, not semantic matches. If you need
  "count evens", count a filtered collection first.
- When the final response only needs existing values, configure `output.response_body` or
  `output.selected_variables` directly instead of inserting a pass-through `text_template`
  or `set_variable` node.
- After `unique`, `sort`, `limit`, `filter`, or similar transforms, recompute expected
  constants from the exact post-transform dataset that reaches the assertion or output.
- When mutually exclusive branches set the same global names, reference those shared globals
  downstream instead of concatenating branch-specific placeholders.
- Always pass `near_node_id` when adding a node so the canvas stays readable.
- Once a flow is already valid and request-complete, stop. Do not spend extra tool calls on
  `list_node_variables`, `read_mission_flow`, or another patch merely to reassure yourself that
  the same valid flow is still valid.
