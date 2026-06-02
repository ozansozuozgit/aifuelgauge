# AI Fuel Gauge — Redesign Design

**Date:** 2026-06-02
**Status:** Approved (brainstorm), pending implementation plan
**Reference:** `handoff/HANDOFF.md`, `handoff/source/` (HTML/React prototype), `handoff/screenshots/`

## 1. Goal & scope

A single-pass, **faithful-but-native** SwiftUI rebuild of the two surfaces in
`Sources/AIFuelGaugeApp/main.swift`: the **menu-bar popover** and the **Settings
window**, plus a restyled **History window**.

The data layer is **out of scope and unchanged**: `DashboardController` /
`DashboardViewModel`, the connectors (Codex, Cursor, Claude Code, OpenRouter,
OpenAI), `AgentWorkbench`, `UsageBudgeting`, history stores. The existing model
already exposes everything the new UI needs — `primaryGauge`, `rows`
(`DashboardRow`: title, value, detail, meterPercent, meterLabel, paceCaption,
receiptText, confidence, state, dashboardURL), `insight`, `state`, workbench, and
history dashboards. This is a presentation-layer redesign.

### Decisions locked in brainstorming

| Decision | Choice |
|---|---|
| Scope/sequencing | Everything (popover + settings + history) in one pass |
| Visual fidelity | Faithful to prototype, native-adapted where SwiftUI diverges |
| Pin vs menu-bar label | **Settings → Menu Bar drives the menu-bar label; the popover hero focus pin is independent (in-popover only)** |
| Featured vs Top-3 hero toggle | **Both** — a quiet in-popover toggle *and* a Settings default |
| History window | Restyle to the new design language |
| Light/dark theme | Follow the system color scheme automatically (no manual control) |
| `main.swift` split | Split into `DesignSystem.swift` (core) + `Popover.swift` + `Settings.swift` (app), trimming `main.swift` |

## 2. Design system — `Sources/AIFuelGaugeCore/DesignSystem.swift`

A central token layer so every view reads from one source and both themes follow
the system color scheme. Lives in the **core** target so it is shareable and
unit-testable. Color tokens are converted from the prototype's oklch values
(`handoff/source/assets/app.css`) to sRGB and resolved per-appearance via dynamic
`NSColor` providers wrapped as SwiftUI `Color`.

**Semantic state palette** (`FuelColor`) — converted from oklch, light + dark variants:

| Token | Meaning | Light (oklch) | Dark (oklch) |
|---|---|---|---|
| `safe` | plenty of room (green) | `0.66 0.15 150` | `0.72 0.16 150` |
| `caution` | getting tight (amber) | `0.74 0.14 80` | `0.80 0.14 82` |
| `critical` | almost out (red-orange) | `0.64 0.18 38` | `0.70 0.18 38` |
| `exhausted` | spent (dark red) | `0.52 0.18 25` | `0.62 0.19 25` |
| `unknown` | local estimate / no limit (gray) | `0.62 0.012 260` | `0.68 0.012 260` |
| `accent` | interactive / primary | `0.55 0.16 256` | `0.68 0.15 256` |
| `accentSoft` | active-nav / chip fill | `accent / 0.12` | `accent / 0.18` |

oklch→sRGB conversion is done at implementation time (oklch → OKLab → linear sRGB →
gamma) and the resulting RGB constants are committed in `DesignSystem.swift` with a
comment citing the source oklch.

**Surfaces & lines** — light/dark hex straight from the prototype CSS:
`canvas`/`canvas2`, `surface`, `surfaceRaised`, `surfaceSunken`, `surfaceHover`,
`material`, `text`/`text2`/`text3`, `border`/`borderStrong`/`divider`, `field`/
`fieldBorder`, `track`.

**Typography** — `Font` helpers. SF system stack for all text. **Monospaced**
(`.system(..., design: .monospaced)`) for every number, %, $, and reset value —
matches the prototype's mono number treatment.

**Geometry** — radii `sm: 6`, `md: 10`, `lg: 14`, `xl: 18`; two shadow styles
`shadowPop` (popover) and `shadowWin` (window).

**State helpers** — extensions mapping `UsageState → FuelColor` and `Confidence →
(label, glyph, color)` so gauges, meters, sparklines, and trust chips color from
one place.

**Native adaptation:** system toggles for switches, SwiftUI `Picker(.segmented)` for
segmented controls, and `.regularMaterial` for the title-bar / menu-bar strips where
that reads more native than hand-rolled equivalents.

## 3. Popover redesign — `Sources/AIFuelGaugeApp/Popover.swift`

Rebuilds `DashboardView` and its subviews. Top → bottom (screenshots 02–04, 14):

1. **Header** — brandmark + "AI Fuel Gauge"; "N lanes live · updated Xm ago";
   trailing **`StatePill`** ("Almost out", colored by `model.state`).
2. **Hero card** — two layouts, selected by a quiet in-popover toggle whose default
   comes from Settings:
   - **`HeroFeaturedCard`** — large 259° **`ArcGauge`** (value sweep colored by
     state; centered mono value + "USED" caption); "TIGHTEST LANE" eyebrow;
     provider title + window/plan subline; an **`Auto ▾` `FocusPill`** to pin any
     provider as the hero focus (**in-popover only — does not change the menu bar**);
     a recommendation chip sourced from `model.insight`; "Resets in …" line.
   - **`HeroTrioCard`** — three equal compact `ArcGauge`s for the three tightest
     lanes, each with title, window, and reset.
   - The featured lane / top-3 selection derives from the existing
     `primaryGauge` + sorted `rows`. A small core helper computes the ordered
     tightest-lane list and resolves the active hero focus (Auto vs pinned).
3. **Lane toolbar** — "LANES" eyebrow + `Usable / All` segmented filter + count
   badge; reorder and details toggles. Existing filter/reorder/details behavior is
   preserved.
4. **Lane list** — **`LaneRow`**: state dot, title + window, **`Meter`** (linear
   capsule, state-colored; **striped variant** for unknown/no-limit), mono value,
   **`TrustChip`** (Exact = seal/green, Estimate = info/gray), and pin / copy / open
   buttons. Under the per-row details toggle: **`Sparkline`** (7-pt trend) + pace
   note + sanitized receipt line.
5. **`ResetContextStrip`** — three reset cards (next reset + per-provider),
   restyled.
6. **`WorkbenchSection`** — collapsible sessions / dev servers / routes, restyled to
   new cards (existing `AgentWorkbench` data).
7. **`ActionBar`** — labeled **Refresh / Settings / History** plus a quiet overflow
   cluster (copy snapshot / about / quit); trailing trust tally line
   ("6 exact · 1 estimated · 1 no limit — all data local").

**New reusable views:** `ArcGauge`, `Meter`, `Sparkline`, `TrustChip`, `StatePill`,
`FocusPill`, `HeroFeaturedCard`, `HeroTrioCard`, `LaneRow`, `ResetContextStrip`,
`ActionBar`. These supersede the current `MiniMeter`, `UsageSparkline`, `StatePill`,
`InsightStrip`, `SourceRowView`, `FooterButton`.

## 4. Settings redesign — `Sources/AIFuelGaugeApp/Settings.swift`

Replace the single 12-panel scroll with a **`NavigationSplitView`** sidebar → detail
(screenshots 05–12, 15).

- **Sidebar** — brand header ("AI Fuel Gauge") + sections **General · Providers ·
  API Keys · Alerts · Menu Bar · Budgets · Data & Privacy · About**; footer
  "Local-first · vX.Y.Z". Active row uses `accent`.
- **Form kit** — `SettingsGroup` (titled card section), `SettingsRow`
  (label + helper text + trailing control), `Switch` (iOS-style), `Segmented`,
  `KeyField` (secure field + Connected state + sanitized status line).
- **Panes:**
  - **General** — refresh cadence (`1m / 3m / 5m / 15m` segmented) + start-at-login
    switch.
  - **Providers** — monitored-source toggles with plan badges (Plus / Pro / Max 5x /
    needs key) + helper lines; plan-label overrides section.
  - **API Keys** — `KeyField` per provider with "Connected" state + sanitized status.
  - **Alerts** — alert-profile rows (per the existing alert model).
  - **Menu Bar** — **owns the menu-bar label.** Live **preview**; `Label detail`
    segmented (Detail / Pair / Trend / Compact / Min); **`Provider focus`** segmented
    (Auto / Codex / Cursor / Claude) — **drives the menu bar, independent of the
    popover hero**. Also hosts the **hero-layout default** (Featured / Top-3).
  - **Budgets** — monthly guardrail fields (OpenAI / Cursor / OpenRouter); blank =
    show spend only, never an invented limit.
  - **Data & Privacy** + **About** — restyled, same content.

`SettingsView` becomes the split-view container; existing panel content/bindings are
re-housed into the new form kit. `EditablePlanRow`, `EditableTextPlanRow`,
`ProviderMonitorRow`, `AlertProfileRow` are adapted to the new row styling.

## 5. History window

Restyle `HistoryWindowView`, `HistoryLaneCard`, `HistoryMetricPill` to the new
tokens/cards. Same data (`UsageHistoryDashboard`), new look — so it stops reading as
the old app.

## 6. Persisted preferences

New `AppPreferences` keys (matching existing patterns):
- `heroLayout` — `featured` | `trio` (Settings default; popover quick-toggle writes
  through to it).
- `menuBarProviderFocus` — `auto` | provider id (drives the menu-bar label).
- `menuBarLabelDetail` — `detail` | `pair` | `trend` | `compact` | `min`.

The in-popover hero focus pin is **transient view state**, not persisted, and never
touches `menuBarProviderFocus`.

## 7. Testing & verification

- Core logic is unchanged → existing `AIFuelGaugeCoreTests` must stay green
  (`swift test`).
- New core helpers (tightest-lane ordering, hero-focus resolution, top-3 selection,
  menu-bar label formatting per `labelDetail`/`providerFocus`) get unit tests in the
  core target.
- `DesignSystem` oklch→sRGB constants get a sanity test (values in range, light ≠
  dark where expected).
- Visual verification: build + run; compare popover (featured / top-3 / details +
  workbench), each settings pane, and history against the screenshots in both light
  and dark.
- No snapshot-test infrastructure exists and none is added unless requested.

## 8. File plan

**New**
- `Sources/AIFuelGaugeCore/DesignSystem.swift` — tokens, colors, type, geometry,
  state helpers (core target, shared + testable).
- `Sources/AIFuelGaugeApp/Popover.swift` — `DashboardView` + popover subviews.
- `Sources/AIFuelGaugeApp/Settings.swift` — `SettingsView` split-view + form kit.

**Edited**
- `Sources/AIFuelGaugeApp/main.swift` — keeps `AIFuelGaugeAppDelegate`, window
  wiring, and menu-bar label construction; `DashboardView` / `SettingsView` /
  `HistoryWindowView` move out or are rebuilt. Net effect: `main.swift` shrinks
  substantially.
- `Sources/AIFuelGaugeCore/DashboardViewModel.swift` (or a small new core file) —
  add the hero-focus / tightest-lane / label-format helpers + their tests.

**Out of scope / untouched:** all connectors, `AgentWorkbench`, `UsageBudgeting`,
`UsageModels`, `UsageRefreshReconciler`, history stores, `AppUpdateChecker`.

## 9. Non-goals (YAGNI)

- No manual light/dark toggle (system only).
- No snapshot/UI-test harness.
- No new data sources, connectors, or polling changes.
- No change to the menu-bar label *mechanism* beyond wiring the new
  `providerFocus` / `labelDetail` preferences into the existing formatter.
