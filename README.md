# AI Fuel Gauge

Local-first macOS menu bar app for tracking LLM/API quota and usage.

AI Fuel Gauge answers one question from the menu bar: which AI lane can you
use right now without running into a limit?

## Current v0 scope

- Native macOS menu bar executable using AppKit + SwiftUI.
- Core usage model with explicit confidence: exact, estimated, unknown.
- OpenRouter connector for:
  - `GET /api/v1/key`
  - `GET /api/v1/credits`
- Codex account connector using the local Codex OAuth file at `~/.codex/auth.json`
  and the Codex account usage endpoint.
- Local coding-agent scaffolding:
  - Claude Code JSONL token aggregation from `~/.claude/projects`
  - Codex JSONL rate-limit parsing from `~/.codex/sessions` as fallback
  - OpenCode local database detection at `~/.local/share/opencode/opencode.db`
  - Cursor app detection at `~/Library/Application Support/Cursor`
  - Cursor plan/status parsing from `User/globalStorage/state.vscdb`
- Compact dashboard view model and threshold logic.
- Polished popover with a primary usage gauge, subscription plan labels,
  exact/estimated/unknown reliability labels, freshness text, and compact number
  formatting.
- Footer controls for Refresh, Settings, and Quit.
- Settings for editable local plan labels, warning thresholds, and refresh cadence.
- Paste-friendly macOS Keychain storage for an OpenRouter API key.
- Background refresh so opening the menu item does not block on large local logs.
- Optional live OpenRouter polling when a key is saved in Settings.

## Install standalone

Build and install a standalone menu bar app into `~/Applications`, with a
LaunchAgent so it starts at login:

```bash
git clone https://github.com/ozansozuozgit/aifuelgauge.git
cd aifuelgauge
make install
```

The install script builds a release `.app`, copies it to
`~/Applications/AI Fuel Gauge.app`, ad-hoc signs it for local use, and enables:

```text
~/Library/LaunchAgents/com.ozansozuoz.aifuelgauge.plist
```

Uninstall:

```bash
make uninstall
```

Package without installing:

```bash
make package
open dist
```

This is not notarized yet. On first launch, macOS may require you to approve
the app in Privacy & Security.

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

The same commands are available through `make`:

```bash
make test
make run
make package
```

## What The Numbers Mean

- Codex shows remaining capacity first because that matches the Codex menu and
  is easier to act on.
- The 5h lane is the main working-session quota. Weekly is the reserve.
- Codex plan labels come from the account usage response when available. The
  current `prolite` account value is shown as `Pro`.
- Model-specific Codex caps are hidden while unused. If one becomes active, it
  appears as a readable model row, for example `Spark model · 5h`.
- Claude Code uses your editable local plan label. Token totals are estimates
  from local usage metadata, not hard provider limits.
- Cursor reads local Cursor account state for membership type and subscription
  status when available. Cursor quota usage is not connected yet, so the row is
  a subscription label, not a fake limit.
- OpenRouter values are exact when an API key is saved in Settings.

## Product principle

Do not pretend estimates are exact. The app should always distinguish:

- official API values: exact where provider docs support it
- local log totals: estimated usage/cost
- detected-but-unparsed sources: unknown

## Next useful build slices

1. Add a real Cursor usage connector if Cursor exposes quota metadata locally or
   via account APIs.
2. Add FSEvents/polling refresh for Claude/Codex/Cursor local state.
3. Add OpenAI usage/cost connector.
4. Replace OpenCode placeholder with SQLite-backed usage parsing.
5. Add 7-day history bars and per-model cost breakdowns.
6. Add WidgetKit widgets for the active provider and tightest quota.
7. Add Homebrew cask and signed/notarized release builds.
8. Add a proper `.app` bundle icon.
