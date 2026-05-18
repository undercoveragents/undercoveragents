---
name: channel-basics-and-types
description: Use this skill when explaining what channels are, how they differ from connectors, and which shared channel types the product supports.
---

# Channel Basics and Types

Use this skill for general questions about channel publishing in the platform.

## What a channel is

- A channel is a published invocation surface for an agent or mission.
- Channels belong to the current operation, so publication stays scoped to one workspace.
- A channel is different from a connector: the connector handles external access or credentials, while the channel defines how the experience is exposed.

## Shared channel types

- Client-type channels power branded end-user chat experiences.
- API channels expose programmatic invocation paths and channel credentials.
- Plugin-provided channel types may add delivery-specific behavior such as messaging-platform routing, but they still fit the same channel model.

## Practical guidance

- Explain channels as the publishing layer, not as the intelligence layer.
- If the user wants a new public experience, confirm the target channel type before changing the agent or mission itself.
- If setup depends on an outside system, connect the prerequisite connector story before treating the channel as broken.
