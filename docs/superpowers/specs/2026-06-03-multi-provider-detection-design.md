# Multi-Provider Detection Upgrade — Design Spec

**Date:** 2026-06-03
**Status:** IMPLEMENTED 2026-06-03. Phase 1 (Claude) live-verified; Phase 4
(Codex) live-verified; Phase 5 (Cursor) no-op under local-creds-only; Phases 2
(Gemini) + 3 (Copilot) built with unit tests, shipped OFF by default pending
live verification (tools not installed on dev machine). 151 tests pass.
**Author:** Ozan + Claude

## Goal

Make AI Fuel Gauge's usage detection best-in-class versus competitors (notably
CodexBar by steipete) by:

1. Adopting better *zero-setup* detection for providers we already support
   (Claude, Codex, Cursor).
2. Adding the two provider gaps competitors have and we lack: **Gemini** and
   **GitHub Copilot**.

Guiding principle (decided): **local credentials only** — we read only the
credential material the tools themselves already wrote to disk (plus legitimate
OAuth device flow for Copilot). No browser-cookie-vault decryption. This keeps
the app honest, dependency-light, and aligned with our privacy/trust story,
while still capturing ~90% of the detection wins.

This work strengthens our core differentiator: the **trust model** ("X exact ·
Y estimated"). Every new source below is `.exact`, so adopting them visibly
improves the honesty story, not just coverage.

## Non-goals

- Browser cookie extraction / OpenAI web-dashboard scraping (requires decrypting
  Safari/Chrome/Firefox vaults + a heavy dependency). Explicitly out of scope.
- OpenAI admin-key-free usage (depends on the cookie path above). OpenAI stays
  admin-key based, unchanged.
- Multi-account reconciliation / ownership-proof engine (CodexBar's
  `CodexDashboardAuthority`, `CodexVisibleAccountProjection`). Over-scoped for now.
- Any UI redesign. New providers reuse the existing lane/row UI.

## Architecture decision

**Source planner per provider.** Each provider has, potentially, several data
sources at different confidence levels. The connector picks the *best available*
source in a fixed priority order and emits one set of lanes with the correct
`confidence`. This matches our existing refresh loop (each provider already
guarded by `monitoredProviders.contains(...)` in
`Sources/AIFuelGaugeApp/main.swift`) and our trust-chip model, and avoids
duplicate lanes.

Each connector **fails soft**: on any error it appends a warning and returns no
snapshots; it never throws out of the refresh loop. Each provider is
individually toggleable in Settings.

All HTTP goes behind an injectable fetcher protocol so parsing logic is unit
tested offline with JSON fixtures (mirroring our existing connector tests).

These are undocumented/unofficial endpoints. They may change. The soft-fail +
per-provider toggle posture is the mitigation.

---

## Phase 1 — Claude exact usage, zero setup (highest value)

**Problem:** Today we only get exact Claude 5h/weekly % if the user installs our
statusline hook (which injects
`~/Library/Application Support/AI Fuel Gauge/claude-statusline.json`). Without it
we fall back to a `.estimated` token count with no limit and no plan.

**Solution:** Read Claude's *own* OAuth credentials and call Anthropic's usage
endpoint directly — no hook required.

- **Credential discovery (in order):**
  1. `~/.claude/.credentials.json` → parse `claudeAiOauth.accessToken`
     (+ `refreshToken`, `expiresAt`, `subscriptionType`).
  2. macOS Keychain, service `"Claude Code-credentials"`.
- **Fetch:** `GET https://api.anthropic.com/api/oauth/usage`
  - Headers: `Authorization: Bearer <accessToken>`,
    `anthropic-beta: oauth-2025-04-20`.
- **Parse** (`utilization` is already a 0–100 percent, not a token estimate):
  - `fiveHour` → "Claude · 5h" lane
  - `sevenDay` → "Claude · Weekly" lane
  - `sevenDayOpus` / `sevenDaySonnet` → model-specific weekly lanes when present
  - each → `used = .percent(utilization)`, `limit = .percent(100)`,
    `reset = .fixed(resetsAt)`, `confidence = .exact`
  - plan tier from `subscriptionType` / rate-limit-tier → account plan label
    (Pro / Max 5x / Max 20x / Team / Enterprise).
- **Token refresh:** if `expiresAt` is past, attempt refresh
  (`POST https://api.anthropic.com/api/oauth/token` style with `refreshToken`);
  on failure, surface an actionable "open Claude Code to refresh" warning and
  fall back to the next source. (Refresh shape to be confirmed in spike.)
- **`ClaudeSourcePlanner` priority:** oauth-exact → our statusline (exact) →
  JSONL token estimate. The hook stays as a fallback but is no longer required.
- **Reconciliation:** oauth-exact lanes supersede statusline/JSONL lanes for the
  same window so we never show a lane twice.

**Spike first:** a ~10-line throwaway that reads the local creds and hits the
endpoint on Ozan's machine to confirm credential shape, header, and response
JSON before building the connector.

**New/changed files:** `ClaudeOAuthConnector.swift` (new),
`ClaudeSourcePlanner.swift` (new, small), wiring in `main.swift` refresh loop,
`LocalAgentUsage.swift` (planner integration / dedupe).

---

## Phase 2 — Gemini (new provider; `.gemini` enum case already exists)

**Detect:** Gemini Code Assist / Gemini CLI quota.

- **Credential discovery:** `~/.gemini/oauth_creds.json`
  (`access_token`, `refresh_token`, `expiry_date` ms).
- **Use `access_token` directly while unexpired** (no client secret needed for
  the read path).
- **Fetch:**
  - `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`
    body `{}` or `{"project": <id>}` → quota buckets
    (`modelId`, `remainingFraction` 0–1, `resetTime`).
  - `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`
    body `{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}`
    → `currentTier.id` (free/standard/legacy) for plan label, and managed
    project id.
- **Parse:** group buckets by model, keep lowest fraction per model;
  `used = .percent(100 * (1 - remainingFraction))`, `limit = .percent(100)`,
  `reset = .fixed(resetTime)`, `confidence = .exact`. Lanes: Pro / Flash /
  Flash-Lite (those present).
- **Expiry/refresh:** while token valid, no secret needed. On expiry, attempt
  refresh via `https://oauth2.googleapis.com/token` using client id/secret
  extracted from the gemini-cli JS bundle (search `node_modules/@google/gemini-cli`,
  Homebrew/Nix/fnm paths). If extraction fails, surface "run `gemini` to
  refresh" warning and emit nothing (no guessing). Extraction is best-effort and
  isolated so its fragility can't break the read path.

**New/changed files:** `GeminiConnector.swift` (new), Settings toggle,
`main.swift` wiring, `dashboardURL(for:)` case.

---

## Phase 3 — GitHub Copilot (new provider; add `.copilot` enum case)

**Detect:** Copilot premium-request + chat quota.

- **Credential discovery (local-first):**
  1. Reuse existing on-disk GitHub OAuth token:
     `~/.config/github-copilot/apps.json` (or `hosts.json`) → `oauth_token`.
  2. Only if absent, run **GitHub device flow** (legitimate OAuth, not scraping):
     - client_id `Iv1.b507a08c87ecfe98` (VS Code), scope `read:user`
     - `POST https://github.com/login/device/code` → show `user_code` +
       `verification_uri`
     - poll `POST https://github.com/login/oauth/access_token`
       (`grant_type=urn:ietf:params:oauth:grant-type:device_code`), honoring
       `authorization_pending` / `slow_down` / `expired_token`
     - store resulting token in our Keychain.
- **Fetch:** `GET https://api.github.com/copilot_internal/user`
  - Headers: `Authorization: token <token>`, `Accept: application/json`,
    `Editor-Version: vscode/...`, `Editor-Plugin-Version: copilot-chat/...`,
    `User-Agent: GitHubCopilotChat/...`, `X-Github-Api-Version: 2025-04-01`.
- **Parse:** `quota_snapshots.premium_interactions` and `.chat` →
  `percent_remaining` → `used = .percent(100 - percent_remaining)`,
  `limit = .percent(100)`, `reset = .fixed(quota_reset_date)`,
  `confidence = .exact`. Plan from `copilot_plan`. Skip placeholder quotas
  (entitlement 0 / token-based billing) so we don't show fake "0% used".
  Fallback to `monthly_quotas` / `limited_user_quotas` shape if `quota_snapshots`
  absent.

**New/changed files:** `CopilotConnector.swift` (new), `CopilotTokenStore`
(Keychain), `.copilot` in `Provider` enum (+ displayName/shortName), Settings
toggle + connect button, `main.swift` wiring, `dashboardURL(for:)` case.

---

## Phase 4 — Codex hardening

**A. Spark / additional rate limits.** Today we parse 5h/Weekly/Spark loosely.
Parse the response's `additional_rate_limits` array properly:
- Spark → two lanes (5h + weekly) with stable IDs (`codex-spark`,
  `codex-spark-weekly`), window kind detected by `limit_window_seconds`
  (≤ ~6h → 5h; ≥ ~1d → weekly).
- Other model-specific limits → generic lane id `codex-<slug>`.
- Dedupe ids; missing additional limits must not break primary/secondary parsing
  (lossy decode).

**B. Token refresh discipline.** Track `last_refresh` from `auth.json`; only
refresh when older than 8 days (or on 401); coalesce concurrent refresh calls
into one in-flight task (share the result).

**New/changed files:** `CodexUsageConnector.swift` (additional-limit mapper +
refresh TTL/coalescing), tests with response fixtures.

---

## Phase 5 — Cursor richer data (conditional on spike)

**Spike:** does our locally-read vscdb `accessToken` authenticate
`GET https://cursor.com/api/usage-summary` when sent as a
`Cookie: WorkosCursorSessionToken=<token>` header (and/or `Authorization`)?

- **If yes:** switch Cursor to `/api/usage-summary`. It exposes far more:
  `individualUsage.plan` (included), `.onDemand` (overage), `.overall`
  (enterprise personal cap), `teamUsage.pooled` (shared pool), per-model
  `autoPercentUsed`/`apiPercentUsed`/`totalPercentUsed`, and billing cycle.
  Headline percent uses the 5-level fallback: `totalPercentUsed` → avg(auto,api)
  → either lane → plan ratio → overall ratio → pooled ratio. Cents → USD by /100.
- **If no:** keep the current Connect `GetCurrentPeriodUsage` endpoint and only
  adopt the cache discipline below.

**Either way:** on 401/403 clear the cached token immediately; on transient
network failure preserve last-good (we already have a 24h reconciler — keep it).

**New/changed files:** `CursorUsageConnector.swift` (endpoint + richer parse +
cache discipline), tests with `/api/usage-summary` fixtures.

### Phase 5 spike outcome (2026-06-03) — NO-OP under local-creds-only

Spike result: the vscdb `cursorAuth/accessToken` (a JWT) returns **401** against
`https://cursor.com/api/usage-summary`; that endpoint requires the browser
`WorkosCursorSessionToken`, which is out of scope (no browser-cookie extraction).
vscdb exposes only `accessToken` + `refreshToken`. Our **current** Connect
endpoint (`api2.cursor.sh/.../GetCurrentPeriodUsage`) still returns 200, and we
read the token fresh from vscdb every refresh (so we inherit Cursor's own token
refresh) and already preserve last-good for 24h via the reconciler.

Therefore the richer data (included-vs-overage, team pooled, per-model) is
**unreachable without browser cookies**, and the cache-discipline change is moot
(we hold no token cache to invalidate). **Decision: ship no Cursor change.** Our
Cursor detection is already optimal under the chosen constraints. Revisit only if
browser-cookie extraction is ever added.

---

## Data model touchpoints

- `Provider` enum (`UsageModels.swift`): `.gemini` already present; **add
  `.copilot`** with `displayName` / `shortName`.
- No new `UsageQuantity` / `ResetInfo` cases needed — everything maps to existing
  `.percent` / `.usd` and `.fixed` / `.rollingWindow`.
- `confidence = .exact` for all new sources; `source` = `.officialAPI` (or a new
  `.localCredential` label if we want to distinguish — TBD, default `.officialAPI`).

## Refresh-loop integration

Each phase adds a guarded block in `DashboardController.loadUsageOffMain`
(`main.swift`), following the existing Codex/Cursor/OpenRouter/OpenAI pattern:
fetch → on success replace any lower-confidence lanes for that provider → on
error append a warning. New providers also need `monitorXEnabled` keys in
`AppPreferences` and toggles in `Settings.swift`.

## Testing strategy

- Every parser is a pure function over decoded JSON; unit-tested with captured
  fixtures (one happy-path + key edge cases per provider), in the style of
  existing `*ConnectorTests` / `DashboardViewModelTests`.
- Network is behind an injectable fetcher; no test hits the network.
- Source-planner priority/fallback gets its own tests (e.g. Claude: oauth present
  → statusline ignored; oauth absent → statusline used; both absent → estimate).
- Each phase ships green before the next starts.

## Rollout / safety

- Phases are independent and individually shippable.
- Every new connector is behind a Settings toggle (default on for read-from-local
  sources; Copilot device flow is opt-in via connect button).
- Soft-fail everywhere; a broken endpoint degrades one lane, never the app.
- Start each networked phase with a tiny spike to confirm endpoint + payload on a
  real machine before building the connector + tests.

## Open items to confirm during spikes

1. Claude OAuth refresh request shape (endpoint/body) and `expiresAt` field name.
2. Whether Cursor vscdb token authenticates `/api/usage-summary` (Phase 5 gate).
3. Copilot existing-token path file (`apps.json` vs `hosts.json`) and field name.
4. Gemini project-id requirement for `retrieveUserQuota` (empty body vs project).
