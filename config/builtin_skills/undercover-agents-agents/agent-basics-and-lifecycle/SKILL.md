---
name: agent-basics-and-lifecycle
description: Use this skill when explaining what an agent is, how it is configured, and how it moves from setup to real usage.
---

# Agent Basics and Lifecycle

Use this skill for general questions about what agents are and how they fit into the platform.

## What an agent is

- An agent is the main conversational worker the platform exposes to users, admins, or internal product surfaces.
- Agents belong to one operation, so they are part of a specific workspace rather than global shared records.
- An agent combines instructions, model settings, optional tools, optional subagents, and optional skill catalogs.

## How agents are used

- Some agents are user-selectable and appear in testing or chat surfaces.
- Some agents are builtin helpers used by the product itself, such as shared assistants or internal authoring helpers.
- Agents can stay simple and answer with their instructions alone, or they can become more capable through tools, skills, or capabilities.

## Practical guidance

- If someone asks what makes one agent different from another, explain the combination of purpose, tools, knowledge, and model setup.
- Agent model setup can stay single-route or add multi-model routing for fallback, canary rollout, or A/B comparison when the user wants resiliency or evaluation behavior.
- If a user wants a new working behavior, decide whether that belongs in the instructions, a skill catalog, a tool assignment, or a capability.
- If an agent seems to be missing, confirm the current operation before assuming it was removed.
- Agent show pages support a Clone action for creating a new editable copy in the same operation when the user wants a starting point instead of changing the original.
