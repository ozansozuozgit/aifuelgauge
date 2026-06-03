# Security Policy

AI Fuel Gauge is a local-first macOS app. It reads local account state and
optional API keys only to show usage, quota, and spend status on your Mac.

## Data Boundaries

- API keys are stored in macOS Keychain.
- Copied diagnostics and the local `status.json` export are sanitized.
- Prompt text, auth tokens, API keys, and raw provider responses are not written
  to diagnostics or status export files.
- Local Claude Code, Codex, and OpenCode metadata is aggregated for usage
  totals; prompt or transcript text is not surfaced in the UI.
- The app does not send a central telemetry feed.

## Sensitive Files

Depending on the providers you use, the app may read metadata from locations
such as:

```text
~/.codex
~/.cursor
~/.claude
~/.config/opencode
~/Library/Application Support/AI Fuel Gauge
```

The app-owned files are stored under:

```text
~/Library/Application Support/AI Fuel Gauge
~/Library/Logs/aifuelgauge.log
```

## Reporting

Please report security or privacy issues privately by emailing
<ozansozuoz@gmail.com>. Include the affected version, macOS version, steps to
reproduce, and whether any local files, keys, or diagnostics were exposed.

Do not include API keys, auth tokens, prompt text, or raw provider responses in
reports. Sanitized diagnostics from the app are fine.
