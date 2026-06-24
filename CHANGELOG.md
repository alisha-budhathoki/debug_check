# Changelog

## 0.1.0

- Initial extraction from the host app into an isolated package.
- Network/API inspector, log & error console, performance (FPS/jank) monitor,
  layout-grid inspector, and a shareable app-info snapshot.
- Per-tab field & body search in the API detail view with highlighted matches,
  a results list, and prev/next jump-to-match navigation.
- At-a-glance insight chips on each call (slow / server error / cached / large /
  unauthorized) and latency colour-banding in the log list.
- Duplicate API-call detection, and one-tap cURL / JSON / HAR export.
- Fully decoupled from the host: wired through the `DebugTools` facade and a
  host-supplied `DebugAppInfo`. Master switch via `DebugTools.enabled`.
