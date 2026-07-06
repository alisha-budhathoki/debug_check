# Changelog

## 0.5.1

- Reworked the Autopsy so it no longer echoes numbers already shown elsewhere in
  the deck. Findings now read as a **diagnosis + a fix** in plain language
  ("Failures are server-side, not in the app", "The same request is firing more
  than once — debounce or guard it") instead of restating counts you can see in
  the API stats, Perf and Errors tabs.
- Failures are consolidated into a single finding framed by the **dominant
  cause** (server-side 5xx vs. auth vs. client), rather than one line per bucket.
- The grade hero drops the `requests · failed · slowest` strip (already in the
  insight strip / Info tab); the headline now names the **weakest subsystem**
  ("Poor — network is dragging the app down").
- Redundant per-subsystem "all good" findings are gone — a clean run is carried
  by the green subsystem bars plus one honest "Nothing to fix" verdict. The
  Markdown export stays fully self-contained for pasting into a report.

## 0.5.0

- **New: App Autopsy — a one-tap health diagnosis.** A new **Autopsy** tab
  synthesizes everything the deck already captures — network traffic, rendering
  timings and uncaught errors — into a single graded verdict (A–F / 0–100) with
  per-subsystem scores for **Network**, **Rendering** and **Stability**, and a
  prioritized list of plain-language findings (server 5xx, auth rejections, slow
  and duplicate calls, oversized payloads, jank/stalls, crashes). It recomputes
  live as traffic completes and frames land, and exports the whole report as
  **Markdown** for a bug report, PR description or ticket with one tap.
- The diagnosis is a pure, unit-tested function (`AppAutopsy.diagnose`) exposed
  publicly, so you can grade a session programmatically or in tests.
- **New: `DebugTools.breadcrumb(label, [detail])`** — drop a labelled marker
  into the timeline from anywhere. Library-agnostic: call it from a Bloc
  `onTransition`, a Riverpod listener, a Redux middleware or a plain tap handler
  to trace state transitions and user actions alongside API calls and errors,
  without the package ever depending on your state layer. A no-op when disabled.

## 0.4.0

- Reworked the inspector header for a clearer visual hierarchy: the tab switcher
  is now a segmented control sitting directly under the title (the primary
  control), with a per-tab insight strip and the search box below it as a
  contextual layer.
- Added a fixed-height insight strip that summarises the active tab at a glance —
  request / error / latency / transfer / duplicate totals on the log tabs, app
  identity on Info, live FPS / jank / worst-frame on Perf, and device geometry
  on Grid. The header no longer changes height when switching tabs.
- API rows now show the full request origin (`scheme://host`) with a one-tap
  copy-URL button, so the complete URL is legible without opening the detail
  screen.
- The search box stays mounted on every tab but is disabled on the Info / Perf /
  Grid panels, where it has nothing to filter.
- Fixed a crash when `DebugTools.init` ran before the Flutter binding existed
  (e.g. called at the top of `main` before `runApp`); enabling the tools now
  ensures the binding first.

## 0.3.0

- The debug tools can now be toggled on/off at runtime. `DebugTools.enabled` is
  backed by a `ValueNotifier` (`DebugTools.enabledListenable`), and a new
  `DebugTools.setEnabled(bool)` flips it; `DebugToolsHost` rebuilds reactively,
  so the overlay appears/disappears without restarting the app.

## 0.2.3

- Restored the full 20/20 platform-support score by raising the `dio` lower
  bound to `^5.7.0`. Older `dio` releases pulled a web adapter built on
  `dart:html`, which is not WASM-compatible; `dio` 5.7.0+ uses `package:web`,
  so the package is now WASM-ready on the web platform.

## 0.2.2

- Full 160/160 pub.dev score: shortened the package description to the 60–180
  character range, applied `dart format`, and made the package WASM-compatible
  by moving the `dart:io` platform lookups behind a conditional import (web
  builds use a stub).

## 0.2.1

- Docs: the README screenshot gallery now uses absolute image URLs so it renders
  on the pub.dev page (in addition to the Screenshots carousel).

## 0.2.0

- Insight chips on the API detail header — auto-derived `SLOW`, `SERVER 500`,
  `NOT MODIFIED · CACHED`, `LARGE`, `UNAUTHORIZED` badges so problems read at a
  glance.
- Latency colour-banding in the log list (green → amber → red) plus
  oversized-response flagging, so the slow or heavy call is obvious without
  opening it.
- The floating bug chip now hides while the full-screen viewer is open, so it no
  longer overlaps the header.
- Added a runnable `example/` app and a five-shot screenshot gallery (README and
  pub.dev), generated reproducibly via an integration test.

## 0.1.0

- Initial release: network/API inspector, log & error console, performance
  (FPS/jank) monitor, layout-grid inspector, and a shareable app-info snapshot.
- Per-tab field & body search in the API detail view with highlighted matches, a
  results list, and prev/next jump-to-match navigation.
- Duplicate API-call detection, and one-tap cURL / JSON / HAR export.
- Fully decoupled from the host: wired through the `DebugTools` facade and a
  host-supplied `DebugAppInfo`. Master switch via `DebugTools.enabled`.
