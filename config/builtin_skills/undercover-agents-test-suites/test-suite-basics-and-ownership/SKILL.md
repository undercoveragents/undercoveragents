---
name: test-suite-basics-and-ownership
description: Use this skill when explaining what a test suite is, how it differs from ad hoc testing, and which workspace owns it.
---

# Test Suite Basics and Ownership

Use this skill for general questions about evaluation in the platform.

## What a test suite is

- A test suite is a reusable collection of test cases for an agent or a mission.
- Test suites are operation-scoped records, so they belong to one workspace rather than to the whole tenant.
- A suite turns one-off testing into something repeatable, reviewable, and comparable over time.

## How it differs from ad hoc testing

- Playground is for quick exploratory checks.
- Test suites are for structured assertions, repeated runs, and tracked outcomes.
- Use a suite when the user wants a durable evaluation workflow instead of a one-time conversation.

## Practical guidance

- If the user asks whether behavior still passes after a change, a test suite is usually the right surface.
- If records seem missing, confirm the current operation before assuming the suite was deleted.
- Explain suites as evaluation assets, not as hidden implementation details.