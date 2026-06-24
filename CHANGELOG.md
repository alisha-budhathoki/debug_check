# Changelog

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
