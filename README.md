
# AI Fuel Gauge

[![CI](https://github.com/ozansozuozgit/aifuelgauge/actions/workflows/ci.yml/badge.svg)](https://github.com/ozansozuozgit/aifuelgauge/actions/workflows/ci.yml)
[![Release](https://github.com/ozansozuozgit/aifuelgauge/actions/workflows/release.yml/badge.svg)](https://github.com/ozansozuozgit/aifuelgauge/actions/workflows/release.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](#install)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

AI Fuel Gauge is a local-first macOS menu bar app for people who live inside AI
coding tools. It answers the practical question:

> Which AI lane can I use right now without running into a limit?

It watches Codex, Cursor, Claude Code, OpenRouter, OpenAI, and local agent usage
signals (with experimental Gemini and Copilot support), then turns them into a
compact menu-bar status and a fast popover built for scanning.

Because it reads every engine's exact usage at once, it can do something no
single-provider tool can: the **Fuel Router** recommends which coding engine to
reach for right now — the one with the most headroom at its tightest limit — and
tells you when they are all tight and which frees up soonest.

<p align="center">
  <img
    src="docs/assets/ai-fuel-gauge-popover.png"
    alt="AI Fuel Gauge menu bar popover showing current AI usage lanes, reset times, and source health"
    width="780"
  >
</p>

## Why

Provider dashboards are scattered, quota labels are inconsistent, and local
coding agents often expose just enough metadata to be useful but not enough to
trust blindly. AI Fuel Gauge keeps those differences visible instead of hiding
them behind a fake universal score.

The app is designed around three ideas:

- Show the lane that matters now, directly in the menu bar.
- Keep exact provider data separate from local estimates and unknown sources.
- Make the popover useful in seconds, not after opening five dashboards.

## What It Does

- **Fuel Router**: a "use this engine now" recommendation across every coding
  provider, with a one-click copy of the launch command.
- Adaptive menu-bar label with the tightest useful lane, remaining capacity, and
  reset time.
- Fuel-style meters that fill with what remains and color by urgency, so a full
  green bar means a full tank and a short red bar means almost out.
- Usable and all-lanes filters, plus a per-provider filter to focus a single
  engine, so exhausted or noisy rows do not dominate the default view.
- Header status that names the most constrained lane instead of crying wolf.
- Most-room and tightest-lane guidance so you can choose the right tool for the
  next task.
- Plan labels for Codex, Cursor, and Claude Code, with local overrides where a
  provider does not expose a clean plan name.
- Local 7-day trend history, sparklines, peaks, deltas, and CSV export.
- Pace and spike warnings when recent usage makes a limit likely.
- Agent Workbench context for recent Claude Code and Codex sessions, common
  local agent routes, and localhost dev servers.
- Copyable status summaries and diagnostics that avoid secrets.
- Local `status.json` export for WidgetKit, SketchyBar, Raycast, Ubersicht, or
  any other status surface that wants a simple machine-readable snapshot.
- Settings for provider toggles, refresh cadence, warning thresholds, menu-bar
  display mode, budgets, keys, and start-at-login.

## Supported Sources

| Source | What it can show | Confidence |
| --- | --- | --- |
| Claude Code | 5h, weekly, and per-model (Opus/Sonnet) quota windows, plan tier | Exact from Claude's own local OAuth login — no setup; statusline capture and JSONL token aggregation as fallback |
| Codex account | 5h and weekly quota windows, plan labels, Spark and model-specific caps | Exact when the local Codex account token is available |
| Cursor account | Included usage, auto usage, API usage, spend rows, plan/status hints | Exact when local Cursor auth is available |
| OpenRouter | Key usage and account credits | Exact with a saved API key |
| OpenAI | Organization costs and completions usage | Exact with a saved Admin key |
| OpenCode | Local SQLite token aggregation | Estimated |
| Gemini *(experimental, off by default)* | Code Assist per-model quota from the Gemini CLI login | Exact when `~/.gemini/oauth_creds.json` is present |
| Copilot *(experimental, off by default)* | Premium and chat request quota | Exact when a local GitHub Copilot token is present |

Exact means the app is reading a provider/account endpoint or documented local
account state. Estimated means the app is aggregating local usage metadata.
Unknown means the source is detected but the app cannot safely turn it into a
quota or usage row.

Gemini and Copilot are built against documented shapes but are not yet verified
against live accounts, so they ship off by default. Enable them under
**Settings -> Providers** once you have those tools installed.

## Privacy Model

AI Fuel Gauge is local-first.

- API keys are stored in macOS Keychain.
- Cursor and Codex auth are read from local account state when available.
- Claude Code exact usage is read from Claude's own OAuth credentials
  (`~/.claude/.credentials.json` or the Keychain item Claude Code already
  stores). When that token is expired, the app refreshes it and writes the
  rotated token back atomically — the same thing Claude Code does — so your
  login stays healthy. Codex tokens are refreshed and written back the same way.
- Claude Code, Codex fallback, and OpenCode usage are aggregated from local
  metadata files.
- Prompt text is not read for status summaries.
- The Agent Workbench uses file names, modification times, paths, process names,
  ports, and file sizes. It does not surface prompt or transcript text.
- Copied diagnostics and `status.json` are sanitized.
- The app does not send a central telemetry feed.

The important boundary: some providers expose exact account usage, while local
logs can only estimate activity. The UI keeps those labels visible so you know
what to trust.

## Install

AI Fuel Gauge requires macOS 14 or newer.

### Homebrew

```bash
brew install --cask https://raw.githubusercontent.com/ozansozuozgit/aifuelgauge/main/Casks/ai-fuel-gauge.rb
```

Open **AI Fuel Gauge** from Applications after installing.

Homebrew installs the app bundle. Start-at-login can be enabled from
**Settings -> General** after first launch.

### From Source

```bash
git clone https://github.com/ozansozuozgit/aifuelgauge.git
cd aifuelgauge
make install
```

`make install` builds a release app, copies it to:

```text
~/Applications/AI Fuel Gauge.app
```

It also installs and starts this LaunchAgent:

```text
~/Library/LaunchAgents/com.ozansozuoz.aifuelgauge.plist
```

The in-app start-at-login toggle creates or removes the same LaunchAgent for
future logins without restarting the app that is currently running.

Uninstall:

```bash
make uninstall
```

Package without installing:

```bash
make package
open dist
```

## Configure

Most setup happens in the popover Settings screen.

- Save OpenRouter and OpenAI keys only after the app successfully tests them.
- Enable or disable providers you do not want polled.
- Set local plan labels for sources that do not expose a reliable plan name.
- Add optional monthly budgets for spend rows such as OpenAI, Cursor, or
  OpenRouter so they can become comparable warning lanes.
- Choose how much detail the menu bar should show: detail, pair, sparkline,
  compact, or minimal.
- Turn start-at-login on or off without touching the terminal.

### Claude Code exact usage

Exact Claude usage now works with **no setup**. If you are signed into Claude
Code, AI Fuel Gauge reads its OAuth credentials locally and fetches exact
`5h`, `Weekly`, and per-model (`Opus`/`Sonnet`) usage directly from Anthropic's
usage endpoint, including your plan tier. Nothing to install, no hook required.

AI Fuel Gauge picks the best Claude signal available, in order:

1. **OAuth usage (exact, zero setup)** — read from Claude's own
   `~/.claude/.credentials.json` (or the Keychain item it stores). The token is
   refreshed and written back atomically when expired, exactly as Claude Code
   does, so your login keeps working.
2. **Statusline capture (exact, optional)** — the legacy path below, kept as a
   fallback.
3. **Local JSONL token totals (estimated)** — token volume from
   `~/.claude/projects`, including `claude -p` / SDK / headless runs labeled
   `print/headless tokens`. Useful for volume, not official quota.

You usually do not need the statusline hook anymore. It remains available under
**Settings -> Enable Claude exact usage** for setups where the OAuth path is not
desired; it installs `~/.claude/aifuelgauge-statusline.py`, updates
`~/.claude/settings.json`, and writes captured quota to
`~/Library/Application Support/AI Fuel Gauge/claude-statusline.json` (documented
quota fields, reset times, session id, model name, timestamp — no prompt text).

## Status Export

Every refresh writes a sanitized machine-readable snapshot:

```text
~/Library/Application Support/AI Fuel Gauge/status.json
```

It includes the menu title, state, primary lane, next resets, visible lanes,
setup guidance, and trend samples. It does not include API keys, auth tokens,
prompt text, or raw provider responses.

## Agent Workbench

The popover includes a compact local workbench beside the usage lanes:

- Recent Claude Code and Codex session files, ordered by local modification time.
- Quick routes for agent skills, plugins, config, logs, and local app state.
- Localhost dev servers on ports 3000-9999, with open, copy URL, and stop
  actions.

This is intentionally passive. AI Fuel Gauge does not install permission hooks
or take over agent prompts; it keeps nearby context visible so quota decisions
are easier while the usage meter remains the main product surface.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full local workflow and privacy
expectations for changes.

Run tests:

```bash
swift test
```

Run the app locally:

```bash
scripts/dev-run.sh
```

The helper script stops any stale debug build from this repo before launching
the fresh one. The same commands are available through `make`:

```bash
make test
make run
make package
make release-zip
```

SwiftPM package layout:

```text
Sources/AIFuelGaugeApp      Native AppKit/SwiftUI menu bar app
Sources/AIFuelGaugeCore     Connectors, budgeting, history, view models
Tests/AIFuelGaugeCoreTests  Parser, connector, dashboard, packaging tests
scripts                    Packaging, install, release, and dev helpers
Casks                      Homebrew cask
```

## Release

Push a version tag to build and publish a GitHub release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow runs tests on macOS, builds `AI Fuel Gauge.app`, uploads
versioned and stable `AI-Fuel-Gauge-latest.zip` artifacts, and attaches SHA-256
checksums.

Tagged public releases require signing and notarization secrets. The workflow
signs with hardened runtime, submits the app to Apple notarization, staples the
ticket, and publishes the notarized zip. Manual workflow runs can still produce
ad-hoc artifacts for testing, but public tags should ship notarized builds.

## Roadmap

- Verify Gemini and Copilot against live accounts and graduate them from
  experimental to on-by-default.
- Burn attribution: correlate the Agent Workbench sessions with usage deltas to
  show which project or session is eating your quota.
- Optional Fuel Guard hook that warns inside the CLI before a run that would blow
  a weekly cap.
- Native WidgetKit companion that reads the local status export.
- Better history views for comparing burn rate across tools.
- Optional update flow for Homebrew or GitHub release installs.

## License

MIT. See [LICENSE](LICENSE).
