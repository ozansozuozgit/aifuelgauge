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
- Polished popover with a primary usage gauge, exact/estimated/unknown reliability labels, freshness text, and compact number formatting.
- Footer controls for Refresh, Settings, and Quit.
- macOS Keychain storage scaffold for an OpenRouter API key.
- Background refresh so opening the menu item does not block on large local logs.
- Optional live OpenRouter polling when a key is saved in Settings.

## Run

```bash
cd ~/programming-files/aifuelgauge
swift test
swift run aifuelgauge
```

The app runs as a menu bar accessory. Use the popover footer to refresh, open settings, or quit.

For local iteration, prefer:

```bash
scripts/dev-run.sh
```

That kills any stale SwiftPM debug `aifuelgauge` process from this repo before launching the fresh build.

## Product principle

Do not pretend estimates are exact. The app should always distinguish:

- official API values: exact where provider docs support it
- local log totals: estimated usage/cost
- detected-but-unparsed sources: unknown

## Next useful build slices

1. Add FSEvents/polling refresh for Claude/Codex local logs.
2. Add OpenAI usage/cost connector.
3. Replace OpenCode placeholder with SQLite-backed usage parsing.
4. Add threshold notifications for 75%, 90%, and exhausted states.
5. Add launch-at-login and a proper `.app` bundle icon.
6. Package as a `.app` bundle, then sign/notarize later.
