# Changelog

## 0.1.0

- Initial extraction from the host app into an isolated package.
- Network/API inspector, log & error console, performance (FPS/jank) monitor,
  layout-grid inspector, and a shareable app-info snapshot.
- Fully decoupled from the host: wired through the `DebugTools` facade and a
  host-supplied `DebugAppInfo`. Master switch via `DebugTools.enabled`.
