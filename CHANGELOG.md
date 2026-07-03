# Changelog

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
