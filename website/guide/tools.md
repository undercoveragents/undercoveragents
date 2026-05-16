# Tools

Tools are the capability layer that agents use to do real work.

They bridge the gap between language-model reasoning and actual system behavior by exposing controlled access to data, services, and execution flows.

## What tools are for

An agent without tools can explain and summarize.

An agent with tools can query data, call external systems, retrieve knowledge, trigger mission logic, and operate against real platform resources. In Undercover Agents, tools are the controlled interface between an agent and the outside world.

## Tool types in the platform

The platform supports multiple kinds of tools, including:

- SQL-backed query tools
- MCP-backed tools
- RAG-backed retrieval tools
- mission-backed tools

Each tool type keeps its own configuration and runtime behavior while still fitting into a shared admin model.

## Why tools matter here

Undercover Agents uses a plugin-backed tool architecture so teams can add capability without turning the application into a tangle of conditional logic.

That matters because real AI products need clear boundaries around what an agent can access. Tools make those boundaries explicit. They also make them manageable: you can inspect them, enable them, disable them, and assign them to agents deliberately.

## Runtime behavior

When an agent calls a tool, the action becomes part of the product runtime.

That means tool execution can be surfaced in chat, streamed in timelines, grouped for readability, and reviewed later. This is a major part of making the platform operational instead of purely experimental.

## Product role

Tools turn Undercover Agents from a prompt-management interface into a working platform.

They are the surface where data access, external integrations, and reusable capability come together in a way that agents can actually use safely.