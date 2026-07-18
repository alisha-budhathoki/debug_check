import 'dart:async';

import 'package:dio/dio.dart' show Interceptor;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_info/app_info_snapshot.dart';
import '../grid/debug_grid_overlay.dart';
import '../logging/debug_dio_interceptor.dart';
import '../logging/debug_logger.dart';
import '../logging/redaction.dart';
import '../navigation/screen_tracker.dart';
import '../overlay/debug_overlay.dart';
import '../performance/perf_monitor.dart';
import '../persistence/session_store.dart';

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

  /// How secrets are masked before they enter the log buffer. Secure by
  /// default: auth headers, cookies and token-ish query params are masked, so
  /// the cURL/JSON/HAR exports are safe to paste into a bug report without the
  /// consumer having to know to configure anything.
  ///
  /// Add bespoke names with `DebugRedaction.standard(also: {...})`, or opt out
  /// entirely with [DebugRedaction.disabled].
  static DebugRedaction redaction = DebugRedaction.standard();

  /// Whether the user has chosen to reveal masked values right now.
  ///
  /// Only meaningful under [RedactionMode.hide], where the raw value was
  /// retained. Drives the eye toggle in the Headers view; resets to hidden on
  /// every launch so revealing is always a deliberate act, never a state you
  /// forgot you left on.
  static final ValueNotifier<bool> revealSecrets = ValueNotifier<bool>(false);

  /// Whether the session's tail is written to disk so the next launch can show
  /// what the run that crashed was doing.
  ///
  /// Off by default: it persists request and response bodies, which is a call
  /// the app should make knowingly. No-op on web — see [SessionStore].
  static bool persistSession = false;

  /// Whether the floating chip is hidden ("get out of my way" for a
  /// screenshot). Exposed so a host app can wire its own restore gesture —
  /// hiding used to be a one-way trip recoverable only by toggling [setEnabled].
  static final ValueNotifier<bool> overlayHidden = ValueNotifier<bool>(false);

  /// Brings the chip back after [overlayHidden].
  static void showOverlay() => overlayHidden.value = false;

  /// The version of [map] that should be shown on screen or written to an
  /// export, honouring both the configured [redaction] and the user's current
  /// [revealSecrets] preference.
  ///
  /// Under [RedactionMode.drop] the stored map is already masked and is
  /// returned untouched; under [RedactionMode.off] nothing was ever masked.
  /// Only [RedactionMode.hide] has a decision to make.
  static Map<String, String>? visible(Map<String, String>? map) {
    if (!redaction.canReveal) return map;
    return revealSecrets.value ? map : redaction.apply(map);
  }

  /// Master switch read by every tool. False ⇒ no logging, no overlay, no
  /// perf capture, no work of any kind.
  static bool get enabled => enabledListenable.value;

  /// Wire up the tools. Safe to call once; repeated calls just refresh config.
  static void init({
    required bool enabled,
    DebugAppInfo? appInfo,
    DebugRedaction? redaction,
    bool persistSession = false,
  }) {
    if (appInfo != null) DebugTools.appInfo = appInfo;
    if (redaction != null) DebugTools.redaction = redaction;
    DebugTools.persistSession = persistSession;
    setEnabled(enabled);
    // Fire-and-forget: startup must not wait on disk. The viewer is reactive,
    // so restored entries simply appear when the read completes.
    if (enabled && persistSession) {
      unawaited(DebugLogger.instance.restorePreviousSession());
    }
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

  /// Drop a labelled marker into the log/activity timeline — a state-management
  /// transition, a user action, a feature-flag flip, anything worth a trail.
  /// Deliberately library-agnostic: call it from a Bloc `onTransition`, a
  /// Riverpod listener, a Redux middleware or a plain button handler, and it
  /// shows up interleaved with API calls and errors — and in the Autopsy's
  /// context — without the package ever depending on your state layer.
  ///
  /// ```dart
  /// DebugTools.breadcrumb('CartBloc', 'AddItem(sku: 42)');
  /// DebugTools.breadcrumb('Tapped “Checkout”');
  /// ```
  ///
  /// A no-op when [enabled] is false, so it is safe to leave in shipping code.
  static void breadcrumb(String label, [String? detail]) {
    if (!enabled) return;
    DebugLogger.instance.logInfo(label, detail);
  }

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
