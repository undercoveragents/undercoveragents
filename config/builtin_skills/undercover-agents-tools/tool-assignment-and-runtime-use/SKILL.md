---
name: tool-assignment-and-runtime-use
description: Use this skill when explaining how tools are attached to agents or mission steps and what users should expect at runtime.
---

# Tool Assignment and Runtime Use

Use this skill for questions about how a tool becomes available during real work.

## Where assignment happens

- Agents can be given tool access so they can act during conversations.
- Mission steps can also be configured to use tools when a workflow needs structured actions mid-run.
- Assignment should stay intentional: only attach the tools the agent or mission really needs.

## What runtime use looks like

- Tool calls appear as part of the conversation or run history so operators can understand what happened.
- Good tool use should feel like a visible, reviewable step rather than hidden magic.
- Builtin runtime tools and user-managed tools can both appear in the same overall experience.

## Practical guidance

- If the user wants more reliable action-taking, review tool assignment before rewriting instructions.
- If a mission step should never call tools, leave that step unassigned instead of relying on vague prompt wording.
- Explain tool access as permissioned runtime ability, not as general background knowledge.