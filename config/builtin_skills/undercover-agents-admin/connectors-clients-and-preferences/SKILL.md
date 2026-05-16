---
name: connectors-clients-and-preferences
description: Use this skill when explaining shared integrations, end-user branding, and tenant-wide default model preferences.
---

# Connectors, Clients, and Preferences

Use this skill for questions about shared setup that supports multiple features across the product.

## Connectors

- Connectors represent reusable external integrations such as model providers, databases, authentication systems, or messaging endpoints.
- A connector is usually the first step before a tool, agent, or workflow can use an external system.
- Connectors are tenant-owned shared resources, so they can support many operation-level assets.

## Clients

- Clients define the branded end-user chat experience.
- A client chooses the agent, welcome copy, footer, and branding details that shape the public-facing chat surface.
- Use clients when a tenant needs different end-user experiences without rebuilding the underlying agents.

## System preferences

- System preferences define tenant-wide defaults for model selection, especially when a builtin surface expects a default LLM, embedding model, or image model.
- The default LLM preference also owns temperature, reasoning effort/budget, and provider custom params for agents or mission LLM nodes that choose the system preference source.
- These defaults reduce repeated setup across builtins and shared tooling.

## Practical guidance

- Configure shared integrations first, then attach them to agents, tools, missions, or clients.
- If a builtin feature says a default model is missing, system preferences are the first place to check.
- If the user is asking about branding or welcome copy, guide them to clients rather than agent instructions.
