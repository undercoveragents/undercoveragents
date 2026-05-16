# Agents

Agents are the reusable AI runtime units inside Undercover Agents.

They are not just prompts. An agent combines instructions, model settings, tools, optional skill catalogs, optional subagents, and runtime capabilities into a single object that can be reused across playground chats, client-facing experiences, and internal workflows.

## What agents are for

Agents are where teams define behavior.

Instead of rebuilding the same prompt logic over and over, you create one agent with the right instructions and the right attached capabilities, then reuse it wherever the product needs that behavior.

Typical uses include:

- support and operator assistants
- data-aware copilots
- internal workflow helpers
- mission steps that need LLM reasoning
- tenant-specific assistants with controlled access to tools

## What an agent contains

An agent can bring together several layers:

- base instructions that define tone, rules, and output style
- model selection and runtime configuration
- attached tools for callable capabilities
- skill catalogs for progressive knowledge loading
- subagents for delegation patterns
- capabilities such as chat-title generation or human-in-the-loop behavior

That makes agents the main product surface for defining how the system should think and what it is allowed to do.

## Why this matters in Undercover Agents

Undercover Agents treats agents as product objects, not transient request payloads.

That means agents can be inspected, assigned, tested, reused, and evolved over time. You can connect them to tools, run them in the playground, attach them to clients, or call them inside missions without rewriting the same configuration each time.

## Operational view

The admin surface exposes agents as manageable resources with their own lifecycle.

Teams can:

- create and edit custom agents
- attach tools and skills
- define inputs and behavior boundaries
- test them in the playground
- reuse them inside larger mission graphs

This keeps AI behavior explicit and reviewable instead of hiding it in scattered code or one-off prompts.