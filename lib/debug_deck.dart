/// Isolated, drop-in Flutter debug tools.
///
/// Integration is three lines plus one `init`:
/// 1. `DebugTools.init(enabled: ..., appInfo: ...)` in `main()`.
/// 2. Wrap your app: `MaterialApp.router(builder: (_, child) =>
///    DebugToolsHost(child: child ?? const SizedBox.shrink()))`.
/// 3. `dio.interceptors.add(DebugTools.dioInterceptor())` and add
///    `DebugTools.routeObserver` to your router observers.
library;

// Entry point / facade — the only API most apps touch.
export 'src/core/debug_tools.dart';

// Logging & network capture.
export 'src/logging/debug_dio_interceptor.dart' show DebugDioInterceptor;
export 'src/logging/debug_log_entry.dart';
export 'src/logging/debug_logger.dart';
export 'src/logging/duplicate_calls.dart';
export 'src/logging/log_filter.dart';
export 'src/logging/redaction.dart' show DebugRedaction, RedactionMode;

// Session persistence across restarts.
export 'src/persistence/session_store.dart' show SessionStore;

// Whole-session bug-report export.
export 'src/export/session_export.dart';

// Unified health diagnosis synthesized from network + rendering + errors.
export 'src/autopsy/app_autopsy.dart';

// Performance, app-info, navigation.
export 'src/app_info/app_info_snapshot.dart';
export 'src/navigation/screen_tracker.dart' show CurrentScreenObserver;
export 'src/performance/perf_monitor.dart' show PerfMonitor, PerfStats;

// On-screen tools.
export 'src/grid/debug_grid_overlay.dart';
export 'src/overlay/debug_overlay.dart' show DebugOverlay;
