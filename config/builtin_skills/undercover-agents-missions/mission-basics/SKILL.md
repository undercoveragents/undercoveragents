---
name: mission-basics
description: Use this skill when explaining what missions are, when to use them, and how a workflow differs from a single chat response.
---

# Mission Basics

Use this skill for general questions about what missions are and why someone would choose them.

## What a mission is

- A mission is a reusable workflow made of connected steps.
- Missions are best when the user needs repeatable multi-step behavior, branching logic, data shaping, or longer automated flows.
- A mission is not just one prompt. It is a structured path that can branch, loop, transform data, call tools, and produce final outputs.

## Core building blocks

- Nodes define the work performed at each step.
- Edges define how work moves from one step to the next.
- Inputs bring data into the mission, and outputs define what the run should return.

## When to use a mission

- Use a mission when the user wants a repeatable process rather than a one-off answer.
- Use a mission when multiple steps need to be visible, editable, or testable over time.
- Use a mission when the workflow must branch, aggregate, or pass through distinct transformation stages.

## Practical guidance

- Explain missions as workflows the team can revisit, improve, and debug over time.
- If a user wants a single conversational behavior, an agent may be enough.
- If the user wants a repeatable operating flow, a mission is usually the stronger fit.