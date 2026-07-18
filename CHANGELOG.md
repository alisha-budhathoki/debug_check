# Changelog

## 0.6.1

Documentation only — no code changes from 0.6.0.

- The README now leads with an animated demo of the overlay: the bug chip, the
  inspector, a failing 500 in detail, search inside a response body, the Autopsy
  grade, live FPS and the app-info snapshot. pub.dev has no way to refresh a
  README without a release, which is what this version is for.

## 0.6.0

**Breaking**

- `AppAutopsy.diagnose` no longer takes `duplicates`. It detects duplicate calls
  itself over `entries`; pass `duplicateWindow:` to tune the 5s window. The old
  signature required a map produced by a function that wasn't exported, so
  callers could only pass `const {}` and silently lose the entire duplicate-call
  branch of the network score — the README example never compiled.
- Captured headers and query parameters are **masked by default**. Configure via
  `DebugTools.init(redaction: ...)`, or `DebugRedaction.disabled` to opt out.
- The App Info tab's filter id changed from `info` to `app`. `DebugLogKind.info`
  is what breadcrumbs are, and the panel owning that id is why breadcrumbs never
  got a filter of their own.

**Added**

- **Secret redaction.** The cURL/JSON/HAR exports are meant to be pasted into a
  bug report, and were carrying live `Authorization` headers out of the device.
  `DebugRedaction` masks at *capture* time, so a raw value never enters the
  buffer and can't leak through a screenshot or an export surface added later.
  Masked values keep their shape (`Bearer ••••4f2a`) so a Basic-where-you-
  expected-Bearer bug stays visible; values under 12 characters are masked whole.
- **`RedactionMode`** makes the trade-off explicit, because a secret you can
  reveal later is a secret still in memory: `drop` (default, unrecoverable),
  `hide` (retained, masked, revealable via an eye toggle in the API-detail
  header), `off`. Revealing swaps every surface at once — headers, query, cURL,
  JSON, HAR — so an export can never carry a value the screen calls hidden, and
  resets to hidden on each launch.
- **Session export.** Whole-session Markdown bug report, HAR archive, or
  Autopsy-only, from the viewer header. Also `SessionExport.toMarkdown` /
  `.toHar` as pure functions.
- **Session persistence.** `DebugTools.init(persistSession: true)` writes the
  session tail to disk so the next launch can show what the run that crashed was
  doing. Off by default (it persists bodies), no-op on web, and adds no
  dependency — `dart:io` behind the same conditional import used for platform
  info, so `dio` remains the only dependency.
- **Filtering.** Type (API / Errors / **Events**), status band (2xx–5xx plus
  **Failed** for calls that never got a response), HTTP method, and pinned-only.
  The badge counts axes rather than values, and Apply previews the match count
  so a filtered-empty list can't masquerade as "no logs".
- **Pinning.** Long-press a row to pin it; pinned rows are held back from
  ring-buffer eviction (capped at 50) so the call you're investigating can't
  scroll out of existence. Adds `DebugLogger.togglePin` and `clearUnpinned`.
- `findDuplicateApiCalls` is now exported, alongside a new
  `findDuplicateCallClusters` that returns distinct bursts.
- The overlay's hide button is recoverable: an edge handle restores it, plus
  `DebugTools.overlayHidden` / `showOverlay()`. It used to render nothing with
  no way back, stranding the tools for the rest of the run.

**Fixed**

- `responseBytes` measured the pretty-printed string rather than the payload. A
  4 MB binary download reported 19 bytes (the length of the literal text
  `<binary 4096 bytes>`), and JSON was inflated by indentation. This fed the
  `LARGE` insight chip, the Autopsy's heavy-payload finding and the log
  subtitle — three surfaces giving wrong advice. Now uses `content-length`, then
  the real byte length, and reports nothing rather than a fabricated number.
- The Autopsy's duplicate penalty was roughly 3× too harsh: it counted flagged
  rows while the comment above it said "clusters, not individual flagged rows".
- Breadcrumbs had no way to be filtered to on their own.

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
