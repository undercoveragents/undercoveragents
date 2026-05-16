---
name: tenants-operations-and-access
description: Use this skill when explaining tenants, operations, roles, login flows, and why access differs between users.
---

# Tenants, Operations, and Access

Use this skill for access questions, workspace confusion, and any explanation of who can see or manage what.

## Core concepts

- A tenant is the top-level account boundary. Users, operations, connectors, clients, and system preferences all belong to one tenant.
- An operation is a workspace inside that tenant. Agents, missions, tools, skill catalogs, and RAG flows are scoped to the current operation.
- Headquarter is the tenant's shipped system workspace. Default is the normal starting workspace for day-to-day work.

## Roles

- System administrators can manage tenants globally.
- Tenant administrators manage records inside their own tenant.
- Regular users stay inside the experiences their tenant exposes to them.

## Login and visibility

- Tenant-local users sign in through tenant-specific login URLs.
- Access questions usually reduce to three checks: the user's tenant, the current operation, and the user's role.
- If a user can sign in but cannot see a resource, operation scope is often the reason.

## Practical guidance

- Explain missing data as a scope problem first, not as a system error.
- When someone asks why another tenant's records are unavailable, describe tenant isolation as an intentional safety boundary.
- When a user needs shipped setup surfaces, guide them to Headquarter before exploring custom workspaces.