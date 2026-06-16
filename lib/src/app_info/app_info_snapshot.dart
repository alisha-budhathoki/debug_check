import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:debug_deck/debug_deck.dart';

/// Snapshot of build/platform/device/runtime info, captured on demand. Cheap
/// to construct; the only side effect is recording the very first read time
/// as the app-start timestamp (used for uptime).
///
/// Designed so QA / managers / analysts can read the whole thing at a glance
/// or paste it verbatim into a bug report via `toReadableText`.
class AppInfoSnapshot {
  // Build
  final String version;
  final String buildMode;
  final String environment;
  final String baseUrl;

  // Platform
  final String os;
  final String osVersion;
  final String dartVersion;
  final int processors;
  final String localeName;
  final String timeZoneName;

  // Display
  final Size screenSize;
  final double devicePixelRatio;
  final double textScale;
  final String brightness;
  final String orientation;
  final EdgeInsets safeAreaPadding;
  final EdgeInsets viewInsets; // keyboard etc

  // Accessibility
  final bool accessibleNavigation;
  final bool boldText;
  final bool disableAnimations;
  final bool highContrast;
  final bool invertColors;
  final bool alwaysUse24HourFormat;

  // Runtime
  final DateTime capturedAt;
  final DateTime appStartedAt;
  final Duration uptime;
  final bool isNativeCall;
  final bool? detectedFromNative;
  final String lifecycleState;

  const AppInfoSnapshot({
    required this.version,
    required this.buildMode,
    required this.environment,
    required this.baseUrl,
    required this.os,
    required this.osVersion,
    required this.dartVersion,
    required this.processors,
    required this.localeName,
    required this.timeZoneName,
    required this.screenSize,
    required this.devicePixelRatio,
    required this.textScale,
    required this.brightness,
    required this.orientation,
    required this.safeAreaPadding,
    required this.viewInsets,
    required this.accessibleNavigation,
    required this.boldText,
    required this.disableAnimations,
    required this.highContrast,
    required this.invertColors,
    required this.alwaysUse24HourFormat,
    required this.capturedAt,
    required this.appStartedAt,
    required this.uptime,
    required this.isNativeCall,
    required this.detectedFromNative,
    required this.lifecycleState,
  });

  static DateTime? _appStartedAt;

  /// Should be called from `main.dart` so uptime is accurate; if it isn't,
  /// the first `capture()` call seeds it instead.
  static void markAppStart() {
    _appStartedAt ??= DateTime.now();
  }

  static AppInfoSnapshot capture(BuildContext context) {
    _appStartedAt ??= DateTime.now();
    final media = MediaQuery.of(context);
    final now = DateTime.now();

    return AppInfoSnapshot(
      version: DebugTools.appInfo.version,
      buildMode:
          kDebugMode
              ? 'DEBUG'
              : kProfileMode
              ? 'PROFILE'
              : 'RELEASE',
      environment: DebugTools.appInfo.environmentName,
      baseUrl: DebugTools.appInfo.baseUrl,
      os: _safe(() => Platform.operatingSystem),
      osVersion: _safe(() => Platform.operatingSystemVersion),
      dartVersion: _safe(() {
        final v = Platform.version;
        // Trim "Dart 3.4.0 (stable) (...)" → "3.4.0"
        final match = RegExp(r'^(\S+)').firstMatch(v);
        return match?.group(1) ?? v;
      }),
      processors: _safeInt(() => Platform.numberOfProcessors),
      localeName: PlatformDispatcher.instance.locale.toString(),
      timeZoneName: now.timeZoneName,
      screenSize: media.size,
      devicePixelRatio: media.devicePixelRatio,
      textScale: media.textScaler.scale(14) / 14,
      brightness:
          media.platformBrightness == Brightness.dark ? 'dark' : 'light',
      orientation:
          media.orientation == Orientation.portrait ? 'portrait' : 'landscape',
      safeAreaPadding: media.viewPadding,
      viewInsets: media.viewInsets,
      accessibleNavigation: media.accessibleNavigation,
      boldText: media.boldText,
      disableAnimations: media.disableAnimations,
      highContrast: media.highContrast,
      invertColors: media.invertColors,
      alwaysUse24HourFormat: media.alwaysUse24HourFormat,
      capturedAt: now,
      appStartedAt: _appStartedAt!,
      uptime: now.difference(_appStartedAt!),
      isNativeCall: DebugTools.appInfo.isNativeCall,
      detectedFromNative: DebugTools.appInfo.isNativeCall,
      lifecycleState: WidgetsBinding.instance.lifecycleState?.name ?? 'unknown',
    );
  }

  /// Convenience: are any a11y settings active (worth surfacing to QA when
  /// reproducing user reports)?
  bool get hasAccessibilityOverrides =>
      accessibleNavigation ||
      boldText ||
      disableAnimations ||
      highContrast ||
      invertColors;

  /// True when the soft keyboard is currently pushing the UI up.
  bool get keyboardVisible => viewInsets.bottom > 0;

  static String _safe(String Function() fn) {
    try {
      return fn();
    } catch (_) {
      return '-';
    }
  }

  static int _safeInt(int Function() fn) {
    try {
      return fn();
    } catch (_) {
      return 0;
    }
  }

  String get launchSourceLabel {
    final d = detectedFromNative;
    if (d == null) return 'detecting…';
    return d ? 'native host' : 'Flutter standalone';
  }

  String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String get uptimeReadable => _formatUptime(uptime);

  /// Multi-line plain-text dump suitable for pasting into a bug report.
  String toReadableText() {
    final p = safeAreaPadding;
    final buf = StringBuffer();
    buf.writeln('━━━ APP ━━━');
    buf.writeln('Version: $version');
    buf.writeln('Build: $buildMode');
    buf.writeln('Environment: $environment');
    buf.writeln('Base URL: $baseUrl');
    buf.writeln('isNativeCall: $isNativeCall');
    buf.writeln('Launched from: $launchSourceLabel');
    buf.writeln();
    buf.writeln('━━━ PLATFORM ━━━');
    buf.writeln('OS: $os $osVersion');
    buf.writeln('Dart: $dartVersion');
    buf.writeln('CPUs: $processors');
    buf.writeln('Locale: $localeName');
    buf.writeln('Time zone: $timeZoneName');
    buf.writeln();
    buf.writeln('━━━ DISPLAY ━━━');
    buf.writeln(
      'Screen: ${screenSize.width.toStringAsFixed(0)}'
      '×${screenSize.height.toStringAsFixed(0)} '
      '@${devicePixelRatio.toStringAsFixed(2)}x',
    );
    buf.writeln('Orientation: $orientation');
    buf.writeln('Brightness: $brightness');
    buf.writeln('Text scale: ${textScale.toStringAsFixed(2)}x');
    buf.writeln(
      'Safe area: t=${p.top.toStringAsFixed(0)} '
      'b=${p.bottom.toStringAsFixed(0)} '
      'l=${p.left.toStringAsFixed(0)} '
      'r=${p.right.toStringAsFixed(0)}',
    );
    buf.writeln('Keyboard visible: $keyboardVisible');
    buf.writeln();
    buf.writeln('━━━ ACCESSIBILITY ━━━');
    buf.writeln('Bold text: $boldText');
    buf.writeln('High contrast: $highContrast');
    buf.writeln('Invert colors: $invertColors');
    buf.writeln('Disable animations: $disableAnimations');
    buf.writeln('Accessible navigation: $accessibleNavigation');
    buf.writeln('24h time: $alwaysUse24HourFormat');
    buf.writeln();
    buf.writeln('━━━ RUNTIME ━━━');
    buf.writeln('Lifecycle: $lifecycleState');
    buf.writeln('Started: ${appStartedAt.toIso8601String()}');
    buf.writeln('Captured: ${capturedAt.toIso8601String()}');
    buf.writeln('Uptime: $uptimeReadable');
    return buf.toString();
  }
}
