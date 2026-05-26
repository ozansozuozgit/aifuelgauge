# AI Fuel Gauge

Local-first macOS menu bar prototype for tracking LLM/API quota and usage.

## Current v0 scope

- Native macOS menu bar executable using AppKit + SwiftUI.
- Core usage model with explicit confidence: exact, estimated, unknown.
- OpenRouter connector for:
  - `GET /api/v1/key`
  - `GET /api/v1/credits`
- Local coding-agent scaffolding:
  - Claude Code JSONL token aggregation from `~/.claude/projects`
  - Codex JSONL rate-limit parsing from `~/.codex/sessions`
  - OpenCode local database detection at `~/.local/share/opencode/opencode.db`
- Compact dashboard view model and threshold logic.

## Run

```bash
cd ~/programming-files/aifuelgauge
swift test
swift run aifuelgauge
```

The app runs as a menu bar accessory. Quit it from Activity Monitor for now; a proper Quit item is a near-term TODO.

## Product principle

Do not pretend estimates are exact. The app should always distinguish:

- official API values: exact where provider docs support it
- local log totals: estimated usage/cost
- detected-but-unparsed sources: unknown

## Next useful build slices

1. Add a proper popover footer with Refresh, Settings, and Quit.
2. Store OpenRouter API key in Keychain and fetch real credits.
3. Add FSEvents/polling refresh for Claude/Codex local logs.
4. Add OpenAI usage/cost connector.
5. Replace OpenCode placeholder with SQLite-backed usage parsing.
6. Package as a `.app` bundle, then sign/notarize later.
