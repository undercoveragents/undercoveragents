---
name: mission-runs-and-debugging
description: Use this skill when explaining how missions run, how users read run history, and how to diagnose execution problems.
---

# Mission Runs and Debugging

Use this skill for questions about what happened after a mission was executed.

## What a run shows

- Every mission run represents one execution of the workflow.
- Run history helps users confirm whether the mission completed, failed, or is still progressing.
- A run records enough execution detail to support troubleshooting and repeatable improvement.

## Debugging mindset

- Start with the run status and the latest visible execution clues before changing the flow.
- Use debug-focused views when the user needs to understand which step stalled, branched, or produced unexpected data.
- Treat execution evidence as more reliable than assumptions based on the current canvas alone.

## Practical guidance

- If the user asks whether a mission actually ran, answer from the run history first.
- If the mission stopped early, look for the first step whose outcome no longer matches the intended continuation.
- If the output is wrong, trace the run back to the first transformation that changed the data in the wrong way.