---
name: connectors-channels-and-preferences
description: Use this skill when explaining shared integrations, published channels, end-user branding, and tenant-wide default model preferences.
---

# Connectors, Channels, and Preferences

Use this skill for questions about shared setup that supports multiple features across the product.

## Connectors

- Connectors represent reusable external integrations such as model providers, databases, authentication systems, or messaging endpoints.
- A connector is usually the first step before a tool, agent, workflow, or plugin-owned channel can use an external system.
- Connectors are tenant-owned shared resources, so they can support many operation-level assets.

## Channels

- Channels are published invocation surfaces for agents or missions.
- Client-type channels shape branded end-user chat experiences, while API channels expose programmatic invocations and credentials.
- Some plugin-provided channel types may add extra delivery behavior, but the shared model is still the same: a channel publishes targets inside the current operation.

## System preferences

- System preferences define tenant-wide defaults for model selection, especially when a builtin surface expects a default LLM, embedding model, or image model.
- The default LLM preference also owns temperature, reasoning effort or budget, and provider custom params for agents or mission LLM nodes that choose the system preference source.
- The default LLM preference can also own shared model routing behavior such as fallback, canary rollout, or A/B comparison for system-preference-backed agents or mission LLM nodes.
- These defaults reduce repeated setup across builtins and shared tooling.

## Practical guidance

- Configure shared integrations first, then attach them to agents, tools, missions, or channels.
- If a builtin feature says a default model is missing, system preferences are the first place to check.
- If the user is asking about branding, welcome copy, preview behavior, or the public chat surface, guide them to client-type channels rather than agent instructions.
- If a channel depends on an external service such as Telegram, explain that the connector is a prerequisite and the delivery-specific setup may live in a plugin surface.
