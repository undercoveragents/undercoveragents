---
name: benchmarks-and-behavior-assertions
description: Use this skill when explaining benchmark-style agent suites, behavior assertions, and when fixtures make sense.
---

# Benchmarks and Behavior Assertions

Use this skill for questions about structured agent evaluation beyond a simple expected answer.

## Behavior assertions

- Some agent tests care about how the answer was produced, not only the final text.
- Behavior assertions can verify which builtin child handled the task, whether tool usage appeared, or whether specific keywords must or must not be present.
- These assertions are useful when delegation, tool usage, or guardrails matter as much as the final wording.

## Benchmarks and fixtures

- Benchmark-style suites group scenario keys, categories, and complexity labels so runs can be compared more systematically.
- Fixtures are appropriate when the benchmark needs temporary records such as agents, missions, tools, channels, or skill catalogs created just for the test.
- Fixture-backed runs are for controlled evaluation, not for day-to-day content setup.

## Practical guidance

- Add behavior assertions when the workflow matters, not just the answer.
- Use fixtures only when the scenario genuinely needs temporary surrounding records.
- Explain benchmark metadata as organization and repeatability tooling, not as user-facing production content.