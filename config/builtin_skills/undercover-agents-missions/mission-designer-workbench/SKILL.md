---
name: mission-designer-workbench
description: Use this skill when explaining how to work inside the mission designer, shape a flow safely, and move from idea to valid workflow.
---

# Mission Designer Workbench

Use this skill for questions about how to design or reshape a mission in the mission designer.

## Recommended working style

- Start from the current flow and understand what already exists before changing it.
- Make one coherent set of workflow changes at a time instead of scattering unrelated edits across the graph.
- Treat the returned validation as primary feedback after each meaningful change.

## How to build good flows

- Use clear node names so later debugging and review stay readable.
- Prefer purpose-built nodes before reaching for custom code.
- Add required resources and configuration as part of the same design step, not as a vague follow-up.
- Keep the canvas readable by placing related steps near each other and by keeping branches easy to follow.

## Direct authoring guidance

- Prompts, formulas, and custom code should be authored directly when a step needs them.
- Helper detours are a poor substitute for a clear workflow design.
- Custom code is a last resort when the existing node set cannot express the behavior clearly.

## Practical guidance

- Explain mission editing as an iterative design process: inspect, change, validate, then refine.
- If a warning shows an incomplete path, treat it as a real design issue until the user explicitly wants that path to stop.
- For a concise pre-publish checklist, use the bundled mission review checklist resource in this skill package.