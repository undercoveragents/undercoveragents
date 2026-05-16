# Missions

Missions are the orchestration layer of Undercover Agents.

They let teams design multi-step workflows as visual graphs instead of relying on fragile prompt chains or hidden application logic.

## What missions are for

Missions are the right surface when one model call is not enough.

If a workflow needs branching, retries, loops, HTTP calls, tool execution, structured outputs, or intermediate state, missions provide the model for expressing that work clearly.

## How missions work

The mission designer is a visual canvas built around nodes and connections.

Teams can compose workflows from inputs, agents, LLM steps, tools, control-flow nodes, text templates, JSON extraction, file writing, and outputs. That gives the product a practical way to represent orchestration without burying it in handwritten glue code.

## Why missions matter

Missions move AI work from isolated chat interactions into repeatable operational flows.

Instead of asking an assistant to improvise the same process every time, teams can define the process once and execute it repeatedly with validation, debug visibility, and persisted runtime state.

## Debugging and execution

Undercover Agents treats mission execution as a first-class concern.

Runs can be inspected, debugged, and monitored. Edge state, branching behavior, outputs, and runtime variables are all part of the execution model, which makes missions suitable for real product work instead of demo-only automation.

## Product role

Missions are where the platform becomes an orchestration system.

Agents define behavior, tools expose capability, and missions compose both into a larger execution graph that teams can reason about, improve, and operate over time.