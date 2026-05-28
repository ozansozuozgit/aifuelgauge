# AI Fuel Gauge

Local-first macOS menu bar app for tracking LLM/API quota and usage.

AI Fuel Gauge answers one question from the menu bar: which AI lane can you
use right now without running into a limit?

## Current v0 scope

- Native macOS menu bar executable using AppKit + SwiftUI.
- State-colored menu bar symbol for at-a-glance safe/watch/blocked status.
- Generated app icon included in standalone `.app` bundles and release zips.
- Next-reset timeline for the soonest active provider windows.
- Core usage model with explicit confidence: exact, estimated, unknown.
- OpenRouter connector for:
  - `GET /api/v1/key`
  - `GET /api/v1/credits`
- OpenAI connector for organization usage/cost visibility:
  - `GET /v1/organization/costs`
  - `GET /v1/organization/usage/completions`
- Codex account connector using the local Codex OAuth file at `~/.codex/auth.json`
  and the Codex account usage endpoint.
- Cursor account connector using local Cursor auth state and the current-period
  usage endpoint for exact included/API/auto usage lanes plus response-derived
  spend rows.
- Local coding-agent scaffolding:
  - Claude Code JSONL token aggregation from `~/.claude/projects`
  - Codex JSONL rate-limit parsing from `~/.codex/sessions` as fallback
  - OpenCode SQLite token aggregation from
    `~/.local/share/opencode/opencode.db`
  - Cursor app detection at `~/Library/Application Support/Cursor`
  - Cursor plan/status/auth parsing from `User/globalStorage/state.vscdb`
- Compact dashboard view model and threshold logic.
- Polished popover with a primary usage gauge, subscription plan labels,
  exact/estimated/unknown reliability labels, freshness text, and compact number
  formatting.
- Source-health strip showing live account connectors, local fallbacks, setup
  needed rows, and stale sources at a glance.
- Actionable setup guidance explains missing or fallback sources directly in
  the popover.
- Masked account hints distinguish connected Cursor accounts without exposing
  full emails or tokens.
- Local 7-day persisted sparklines for comparable quota rows so usage drift
  remains visible across app restarts without opening provider dashboards.
- Trend captions under sparklines show 7-day peak and direction at a glance.
- Pace projection warns when the recent burn rate will hit a lane limit before
  its reset.
- History window for local 7-day lane trends, latest value, peak, delta, and
  copyable CSV export.
- Footer controls for Refresh, Settings, History, Report, and Quit.
- Settings for editable local plan labels, warning thresholds, and refresh cadence.
- Per-provider alert profiles so noisy providers can be early, critical-only, or off.
- Configurable menu bar display modes: detail, pair, sparkline, compact, or
  minimal.
- Data controls to reveal or clear the local usage-history file.
- Copyable compact status snapshot plus a full diagnostics report for source
  status, history counts, and current refresh warnings without secrets.
- Paste-friendly macOS Keychain storage for OpenRouter and OpenAI API keys.
- OpenRouter key test action verifies exact usage access before saving.
- OpenAI Admin key test action verifies official cost/usage access before
  saving.
- Cursor live-usage test verifies local account auth and current-period lanes
  without exposing the token.
- Cursor spend rows come from the provider response instead of a hardcoded plan
  budget.
- Background refresh so opening the menu item does not block on large local logs.
- Local source change polling refreshes sooner when Claude/Codex/Cursor state
  changes between normal sync intervals.
- Optional live OpenRouter and OpenAI polling when keys are saved in Settings.

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

Build the same zip artifact used by GitHub releases:

```bash
make release-zip
```

To publish a GitHub release, push a version tag. The release workflow runs
tests on macOS, builds `AI Fuel Gauge.app`, uploads a zipped app artifact, and
attaches a `.sha256` checksum.

```bash
git tag v0.1.0
git push origin v0.1.0
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
- Cursor reads local Cursor account state for membership type, subscription
  status, and auth. When the account endpoint is reachable, it shows included
  total, API usage, and auto usage. If live usage fails, it falls back to a
  subscription label instead of showing a fake limit.
- OpenRouter values are exact when an API key is saved in Settings.
- OpenAI organization cost/token values are exact when an Admin key is saved in
  Settings, but they are shown as spend/activity rows instead of fake quota
  limits.
- OpenCode values are estimated from local SQLite token counters. Costs are not
  estimated yet because OpenCode commonly stores `cost: 0` locally.
- Menu bar display modes control space: Detail shows provider, tightest lane,
  percentage, and reset; Compact drops reset; Minimal shows only percentage.

## Product principle

Do not pretend estimates are exact. The app should always distinguish:

- official API values: exact where provider docs support it
- local log totals: estimated usage/cost
- detected-but-unparsed sources: unknown

## Next useful build slices

1. Add WidgetKit widgets for the active provider and tightest quota.
2. Add Homebrew cask and signed/notarized release builds.
