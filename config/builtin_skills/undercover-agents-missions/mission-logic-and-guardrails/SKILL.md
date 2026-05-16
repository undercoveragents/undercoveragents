---
name: mission-logic-and-guardrails
description: Use this skill when explaining branches, joins, loops, variables, and the common design mistakes that stop a mission from behaving as intended.
---

# Mission Logic and Guardrails

Use this skill when the question is about how workflow logic behaves rather than where to click.

## Branches and joins

- Conditional and choice-based steps should make every meaningful outcome explicit.
- If different paths later meet again, the shared downstream step waits for each still-active path that is meant to arrive there.
- Disabled or intentionally skipped paths should not be treated as blockers.

## Loops and repeated work

- Loop and iterator bodies should stay self-contained.
- Anything that should run once after repeated work finishes belongs on the completion path, not inside the repeated body.
- An output node ends the mission, so it should not be used as a temporary sink inside a loop body.

## Variables and formulas

- Mission variables should come from clear upstream outputs or seeded global inputs.
- Shared downstream logic should rely on shared variables, not on placeholders from mutually exclusive branches.
- Formula fields work best with scalar values. If a step produces a collection or structured object, derive the specific value you need before comparing it.

## Practical guidance

- Explain validation warnings as design feedback, not as optional noise.
- If a path should continue, every true, false, match, error, or done outcome needs an intentional story.
- When a value seems missing downstream, confirm what the upstream step actually exposes instead of guessing the output name.