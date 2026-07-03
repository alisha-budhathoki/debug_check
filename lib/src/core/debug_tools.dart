import 'package:dio/dio.dart' show Interceptor;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_info/app_info_snapshot.dart';
import '../grid/debug_grid_overlay.dart';
import '../logging/debug_dio_interceptor.dart';
import '../logging/debug_logger.dart';
import '../navigation/screen_tracker.dart';
import '../overlay/debug_overlay.dart';
import '../performance/perf_monitor.dart';

/// Host-supplied application facts shown in the Info / Report panels. Keeps the
/// package decoupled from the app: instead of importing the app's config, the
/// app hands these in via [DebugTools.init].
@immutable
class DebugAppInfo {
  final String version;
  final String environmentName;
  final String baseUrl;
  final bool isNativeCall;

  const DebugAppInfo({
    required this.version,
    required this.environmentName,
    required this.baseUrl,
    required this.isNativeCall,
  });

  static const unknown = DebugAppInfo(
    version: '-',
    environmentName: '-',
    baseUrl: '-',
    isNativeCall: false,
  );
}

/// The single entry point and master switch for the package.
///
/// Call [init] once at startup — typically gated on your own dev/staging flag:
///
/// ```dart
/// DebugTools.init(
///   enabled: EnvironmentConfig.isDevelopment,
///   appInfo: DebugAppInfo(
///     version: AppConstants.versionNumber,
///     environmentName: EnvironmentConfig.environmentName,
///     baseUrl: ApiEndpoint.baseURL,
///     isNativeCall: AppConstants.isNativeCall,
///   ),
/// );
/// ```
///
/// Then wire the three integration points: wrap the app with [DebugToolsHost],
/// add [dioInterceptor] to your Dio client, and add [routeObserver] to your
/// router's observers. When [enabled] is false every tool is completely inert.
class DebugTools {
  DebugTools._();

  static final ValueNotifier<bool> enabledListenable = ValueNotifier<bool>(
    false,
  );

  static DebugAppInfo appInfo = DebugAppInfo.unknown;

  /// Master switch read by every tool. False ⇒ no logging, no overlay, no
  /// perf capture, no work of any kind.
  static bool get enabled => enabledListenable.value;

  /// Wire up the tools. Safe to call once; repeated calls just refresh config.
  static void init({required bool enabled, DebugAppInfo? appInfo}) {
    if (appInfo != null) DebugTools.appInfo = appInfo;
    setEnabled(enabled);
  }

  static void setEnabled(bool value) {
    if (enabledListenable.value == value) return;
    enabledListenable.value = value;
    if (!value) return;
    // Enabling wires up tools that touch a binding (perf frame callbacks, error
    // handlers). Consumers naturally call init() at the top of main() — before
    // runApp() — so the binding may not exist yet. ensureInitialized() is
    // idempotent, so this makes init() safe from any point without forcing the
    // consumer to remember the ordering.
    WidgetsFlutterBinding.ensureInitialized();
    AppInfoSnapshot.markAppStart();
    PerfMonitor.instance.start();
    _installErrorHandlers();
  }

  /// Dio interceptor that records every request/response/error into the
  /// inspector. Add it to your Dio client's interceptors.
  static Interceptor dioInterceptor() => DebugDioInterceptor();

  /// NavigatorObserver that labels the current screen in the Perf tab. Add it
  /// to your `GoRouter`/`Navigator` observers.
  static NavigatorObserver get routeObserver => CurrentScreenObserver.instance;

  static bool _errorHandlersInstalled = false;

  /// Chain Flutter + platform error capture into the log console without
  /// swallowing the app's existing handlers.
  static void _installErrorHandlers() {
    if (_errorHandlersInstalled) return;
    _errorHandlersInstalled = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      DebugLogger.instance.logFlutterError(details);
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      DebugLogger.instance.logPlatformError(error, stack);
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }
}

/// Wrap your app's content with this (e.g. in `MaterialApp.builder`). It mounts
/// the layout-inspector scope + the floating debug overlay above your UI when
/// [DebugTools.enabled], and is a transparent pass-through otherwise — so no
/// debug widgets, controllers or listeners exist in the tree in production.
class DebugToolsHost extends StatelessWidget {
  final Widget child;
  const DebugToolsHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DebugTools.enabledListenable,
      child: child,
      builder: (context, enabled, child) {
        if (!enabled) return child!;
        return Stack(
          children: [DebugInspectorScope(child: child!), const DebugOverlay()],
        );
      },
    );
  }
}
