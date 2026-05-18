---
name: api-channels-and-access
description: Use this skill when explaining API channels, published targets, token-based access, and how programmatic invocation differs from a client chat channel.
---

# API Channels and Access

Use this skill for questions about machine-to-machine or backend-driven invocation.

## What API channels provide

- API channels publish agents or missions through a programmatic surface instead of a branded chat page.
- They can expose one or more targets depending on the configured access scope.
- Channel credentials are part of the channel workflow, so operators can rotate access without rebuilding the target itself.

## How access works

- API channels are about controlled invocation, not visual branding.
- Published targets still need to belong to the same operation as the channel.
- Regenerating a token changes access for the caller, so it is an intentional operational action rather than a cosmetic update.

## Practical guidance

- If the user needs backend access to an agent or mission, guide them toward an API channel rather than a client channel.
- If a call fails, confirm the target assignment and current credential before redesigning the underlying agent or mission.
- Explain access scope and published targets as channel-level publication choices, not as model or prompt settings.
