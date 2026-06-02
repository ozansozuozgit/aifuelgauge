# Agent Workbench Design

## Goal

AI Fuel Gauge should take the useful parts of AgentPeek without becoming a
second agent control plane. The app remains a quota and usage decision meter:
the workbench adds nearby context that helps answer which AI lane is practical
right now.

## Chosen Scope

Add a passive Agent Workbench to the popover:

- Recent Claude Code and Codex session files, shown by provider, project, age,
  and log size.
- Quick routes to local agent folders such as skills, plugins, config, logs,
  Cursor state, and OpenCode data.
- Localhost dev server rows for ports 3000-9999 with open, copy URL, and stop
  actions.

## Out of Scope

Permission prompts, question answering, plan approval, diffs, and full tool-call
history are intentionally excluded. Those require CLI hooks and would move AI
Fuel Gauge toward session orchestration instead of usage clarity.

## Data Boundary

The workbench uses file paths, modification times, file sizes, process names,
PIDs, and ports. It does not display prompt text, transcript text, raw diffs, or
raw provider responses.

## Testing

Core tests cover route/session discovery and local dev server parsing. The app
UI is verified through Swift compilation and the existing app test lane.
