---
name: agent-and-mission-test-design
description: Use this skill when explaining how agent and mission test cases are structured and what kinds of expectations belong in each.
---

# Agent and Mission Test Design

Use this skill for questions about how to write effective test cases.

## Agent suites

- Agent test cases center on a prompt plus an expected answer or expected behavior.
- Match style can be stricter or looser depending on whether the team wants exact wording, partial matching, or semantic evaluation.
- Agent suites can also assert behaviors such as expected tools, expected child builtins, or required and forbidden keywords.

## Mission suites

- Mission test cases focus on seeded input variables, expected run status, and expected output variables.
- Mission assertions work best when the suite checks the exact variables the workflow is supposed to produce.
- The mission under test should already expose clear outputs before the suite tries to validate them.

## Practical guidance

- Keep each test focused on one clear behavior or workflow expectation.
- If the assertion is flaky, narrow the expectation before redesigning the whole suite.
- Use the suite type to decide whether the test should assert conversational quality or workflow outputs.