---
name: rag-flow-authoring
description: Use this skill when explaining how a RAG flow is assembled across its stages and what users should decide during setup.
---

# RAG Flow Authoring

Use this skill for questions about how a RAG flow is designed.

## The four stages

- A RAG flow moves through source, chunking, embedding, and storage.
- Each stage has a clear job: gather material, break it into useful pieces, create retrieval-friendly representations, and store the results for later search.
- The exact module choices can vary with the installed feature set, but the stage-based authoring model stays consistent.

## What users decide

- Which source material should be ingested.
- How large or small the retrieved chunks should feel for the target questions.
- Which embedding and storage setup best fits the tenant's retrieval needs.

## Practical guidance

- Explain RAG setup as a pipeline, not as one monolithic setting screen.
- If results feel noisy, chunking and source quality are often the first areas to review.
- If the flow is never run, the downstream retrieval experience will stay stale even if the setup looks complete.
