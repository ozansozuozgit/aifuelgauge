# AI Fuel Gauge — UI/UX Redesign Handoff

A refined-native redesign of the AI Fuel Gauge macOS menu-bar app: the **menu-bar
popover** and a fully restructured **Settings** window. This package is meant as a
build reference — screenshots + a working HTML prototype + this spec.

> The prototype is HTML/React for design review only. Demo data is static. The real
> app is SwiftUI/AppKit (`Sources/AIFuelGaugeApp/main.swift`); use this as the visual
> + interaction target, not as code to port.

---

## What changed & why

**Popover**
- A **hero gauge** anchors the view — one big arc gauge for the lane that matters,
  with a one-line recommendation and reset countdown. Replaces the old flat insight
  strip + buried primary gauge.
- The hero is **not a forced single pick.** A focus selector ("Auto ▾") defaults to
  the tightest *actionable* lane but lets the user pin any provider they live in.
  Every lane row also has a pin button. A **"Top 3" layout** swaps the single gauge
  for three equal compact gauges for people who juggle providers.
- Lane rows: consistent meters, **Exact / Estimate trust chips**, a striped
  "no-limit" bar for unknown sources, sparklines + pace notes under a details toggle.
- Reset timeline strip + a **collapsible Workbench** (sessions / dev servers / routes).
- The 6 cryptic footer icons → a labeled action bar (Refresh / Settings / History)
  plus a quiet overflow cluster, with a local-first trust line.

**Settings** (the big fix)
- The old single 12-panel scroll → **sidebar navigation**: General · Providers ·
  API Keys · Alerts · Menu Bar · Budgets · Data & Privacy · About.
- Dense button rows → proper **form rows** (label + helper + control), iOS-style
  switches, segmented controls, a live menu-bar preview, and key fields with a clear
  "Connected" state + sanitized status lines.

---

## Design tokens

Full set in `source/assets/app.css` (`:root`, `[data-theme="dark"]`). Summary:

**Type** — system stack: `-apple-system, "SF Pro Text", system-ui`. Numbers use a
mono stack (`"SF Mono", ui-monospace`). Used for all gauge values, %, $, resets.

**Brand accent** — a deep, slightly cool blue (interactive elements, active nav,
primary buttons): `oklch(0.55 0.16 256)` light / `oklch(0.68 0.15 256)` dark.

**Semantic state palette** (the gauge meaning — keep these exact):
| State | Light | Meaning |
|---|---|---|
| safe | `oklch(0.66 0.15 150)` (green) | plenty of room |
| caution | `oklch(0.74 0.14 80)` (amber) | getting tight |
| critical | `oklch(0.64 0.18 38)` (red-orange) | almost out |
| exhausted | `oklch(0.52 0.18 25)` (dark red) | spent |
| unknown | `oklch(0.62 0.012 260)` (gray) | local estimate, no limit |

**Surfaces** — layered: `--bg-canvas` (desktop) → `--surface` (window/popover) →
`--surface-raised` (cards/rows) → `--surface-sunken` (sidebar, lane well).
Radii 6/10/14/18px. Soft shadows for the popover and window.

Both **light and dark** themes are fully specified.

---

## Components

| Component | File | Notes |
|---|---|---|
| `ArcGauge` | `data.jsx` | 259° arc, value sweep colored by state, centered value overlay |
| `Meter` | `data.jsx` | linear capsule meter, state-colored |
| `Sparkline` | `data.jsx` | 7-pt trend, state-colored area+line |
| `TrustChip` | `data.jsx` | Exact (seal, green) / Estimate (info, gray) |
| `HeroCard` + `FocusPill` | `popover.jsx` | featured lane + Auto/pin selector |
| `TrioHero` | `popover.jsx` | 3 equal compact gauges (alt hero layout) |
| `LaneRow` | `popover.jsx` | dot + title/window + meter + value + pin/copy/open |
| `ResetStrip`, `Workbench`, `ActionBar` | `popover.jsx` | |
| `Switch`, `Row`, `Group`, `Segmented`, `KeyField` | `settings.jsx` | settings form kit |

Icons are a single stroke-based set in `source/assets/icons.jsx` (24px viewBox,
1.7 stroke). No raster assets.

---

## Key interactions to preserve

1. **Hero focus** — defaults to Auto (tightest actionable lane). User can pin a
   provider via the hero dropdown OR any lane row's pin button. Open question for the
   team: should the pinned choice also drive the **menu-bar label**, or stay
   independent of the popover hero?
2. **Hero layout** — "Featured" (single gauge) vs "Top 3" (three equal gauges).
   In the prototype this is a top-bar toggle; in the app it likely belongs in
   Settings → Menu Bar / Popover, or as a quiet toggle in the popover.
3. **Lane filters** — Usable / All segmented; count badge; reorder + details toggles.
4. **Trust labeling** — never blur Exact vs Estimate vs no-limit. The striped bar +
   chip + footer tally ("6 exact · 1 estimated · 1 no limit — all data local") carry
   the privacy/trust story.
5. **Settings** — sidebar sections, switches, segmented controls, live menu-bar
   preview, key "Connected" state, sanitized status lines.

---

## Screenshots

| File | Shows |
|---|---|
| `01-overview-light.png` | Both surfaces, light |
| `02-popover-featured.png` | Popover, Featured hero (Auto) |
| `03-popover-top3.png` | Popover, Top-3 hero layout |
| `04-popover-details-workbench.png` | Details + Workbench expanded |
| `05`–`12-settings-*.png` | Each settings section, light |
| `13-overview-dark.png` | Both surfaces, dark |
| `14-popover-dark.png` | Popover, dark |
| `15-settings-alerts-dark.png` | Settings, dark |

## Running the prototype
Open `source/AI Fuel Gauge Redesign.html` in a browser. Toggle **Featured / Top 3**
and **Light / Dark** in the top bar. Click the menu-bar gauge to toggle the popover;
use the sidebar to move through settings.
