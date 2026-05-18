---
name: test-runs-and-failure-analysis
description: Use this skill when explaining how test runs are reviewed, what failed, and when a suite problem should be separated from an agent or mission problem.
---

# Test Runs and Failure Analysis

Use this skill for questions about what happened after a suite or test was executed.

## What a run shows

- A test run records the outcome of one suite execution or one selected test execution.
- Run history helps users see whether a case passed, failed, or exposed broader reliability issues.
- The run detail is the evidence source for debugging, not the current editor state alone.

## How to reason about failures

- Start by separating a bad expectation from a real product defect.
- If the suite setup or assertion is wrong, fix the suite.
- If the suite is correct and the target agent or mission is wrong, carry the concrete failure evidence into the next debugging step.

## Practical guidance

- If the user asks what failed, answer from the latest run details first.
- If a failure points to a mission or agent problem, keep the exact failing evidence attached to that handoff.
- Explain repeated failures as a signal to inspect the target behavior, not as proof that the suite feature is broken.