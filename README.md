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
- Optional OpenAI monthly USD budget turns exact spend into a comparable warning
  lane without inventing a provider limit.
- Configurable menu bar display modes: detail, pair, sparkline, compact, or
  minimal.
- Data controls to reveal or clear the local usage-history file.
- App maintenance controls to check the latest GitHub release, open releases,
  copy the Homebrew update command, or reveal the installed standalone app.
- Local `status.json` export for WidgetKit, SketchyBar, Raycast, Übersicht, or
  other status surfaces that need a simple machine-readable snapshot.
- Copyable compact status snapshot plus a full diagnostics report for source
  status, history counts, and current refresh warnings without secrets.
- Primary gauge and widget export include source explanations so the biggest
  number says whether it came from an official API, Cursor auth, local metadata,
  or a fallback.
- Paste-friendly macOS Keychain storage for OpenRouter and OpenAI API keys.
- One-click paste, test, and save flow stores provider keys only after a live
  provider check succeeds.
- OpenRouter key test action verifies exact usage access before saving.
- OpenAI Admin key test action verifies official cost/usage access before
  saving.
- Cursor live-usage test verifies local account auth and current-period lanes
  without exposing the token.
- Cursor detected plan/status can be refreshed in Settings after signing in or
  switching accounts.
- Plan labels show Claude Code from your setting, Codex from the account usage
  response, and Cursor from local account state unless you override it.
- Codex model-specific limits, such as Spark, are explained as separate quotas
  instead of looking like duplicate 5h rows.
- The dashboard separates the lane with the most room from the tightest lane so
  the popover answers both "what can I use now?" and "what should I watch?".
- Cursor spend rows come from the provider response instead of a hardcoded plan
  budget.
- Background refresh so opening the menu item does not block on large local logs.
- Local source change polling refreshes sooner when Claude/Codex/Cursor state
  changes between normal sync intervals.
- Optional live OpenRouter and OpenAI polling when keys are saved in Settings.

## Install standalone

Homebrew cask from this repo:

```bash
brew install --cask https://raw.githubusercontent.com/ozansozuozgit/aifuelgauge/main/Casks/ai-fuel-gauge.rb
```

Or build and install a standalone app from source:

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
tests on macOS, builds `AI Fuel Gauge.app`, uploads versioned and stable
`AI-Fuel-Gauge-latest.zip` app artifacts, and attaches `.sha256` checksums.

```bash
git tag v0.1.0
git push origin v0.1.0
```

Release signing and notarization are optional. If the GitHub repository has the
following secrets, the release workflow imports the Developer ID certificate,
signs with hardened runtime, submits the zip to Apple notary service, staples
the ticket, and then publishes the final zip:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `MACOS_CODESIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Without those secrets, local and CI packaging still works with ad-hoc signing.
Unsigned/ad-hoc builds may require approval in macOS Privacy & Security on first
launch.

## Run

```bash
cd ~/programming-files/aifuelgauge
swift test
swift run aifuelgauge
```

The app runs as a menu bar accessory. Use the popover footer to refresh, open settings, or quit.

The app also writes a sanitized status export on refresh:

```text
~/Library/Application Support/AI Fuel Gauge/status.json
```

That file is intended for widgets and external status bars. It includes menu
title, state, primary lane, next resets, visible lanes, setup guidance, and
trend samples, but not prompts, API keys, auth tokens, or raw provider
responses.

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
  limits unless you set a local monthly USD budget.
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

1. Add a native WidgetKit extension that reads the local status export.
2. Add Sparkle or Homebrew-based update guidance inside the app.
