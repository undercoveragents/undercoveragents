# Guide Overview

Undercover Agents is organized around three core product features:

- Agents define runtime behavior.
- Tools expose capabilities and data access.
- Missions orchestrate multi-step execution.

The pages in this guide explain each of those surfaces in more depth so the product reads like a platform, not a loose collection of screens.

## Product map

### Agents

Agents are the reusable AI units that you assign instructions, model configuration, tools, skills, and capabilities to. They power playground chats, client-facing experiences, and internal automation.

### Tools

Tools are the callable capabilities available to agents. They wrap SQL access, RAG, MCP integrations, mission-backed execution, and other plugin-defined runtime behaviors behind a consistent admin surface.

### Missions

Missions are the orchestration layer. They let teams design visual workflows with control flow, data transformation, HTTP requests, tools, and outputs, so AI work becomes repeatable instead of conversational-only.

## Production build

```bash
pnpm site:build
```

The generated files are written to `website/.vitepress/dist/`.

## Local production preview

```bash
pnpm site:preview
```

or use the tiny static server that the built site also uses:

```bash
pnpm site:serve
```

## Where to edit the site

- Homepage copy and section structure: `website/index.md`
- VitePress config and navbar: `website/.vitepress/config.mts`
- Theme styling: `website/.vitepress/theme/custom.css`
- Feature screenshots: `website/public/images/`
- Marketing service image: `website/Dockerfile`
