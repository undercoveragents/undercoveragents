---
name: rag-runs-and-operations
description: Use this skill when explaining how RAG runs are monitored, how users read progress, and how to reason about ingestion problems.
---

# RAG Runs and Operations

Use this skill for questions about what happened after a RAG flow was executed.

## What a run represents

- A RAG run shows one end-to-end ingestion pass through the configured stages.
- Run history helps users understand whether content was ingested successfully, partially, or not at all.
- Step-level progress is important because a flow can fail or slow down in one stage while the rest of the configuration still looks valid.

## How to troubleshoot

- Start with the run status and stage progress before changing the configuration.
- Ask whether the problem is source access, processing, storage, or expectation mismatch.
- Use recent run evidence to explain stale retrieval results rather than assuming the issue is in the consuming agent.

## Practical guidance

- If knowledge seems outdated, confirm whether the RAG flow has been run recently.
- If a run fails partway through, describe the failing stage before suggesting broader redesign.
- Treat RAG operations as data pipeline work that needs observable run history.
