import 'dart:collection';
import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:debug_deck/debug_deck.dart';

/// One UI/raster frame's timings, in milliseconds, plus the wall-clock-ish
/// raster-finish timestamp used to derive a real (rendered) FPS.
@immutable
class _Frame {
  final double buildMs;
  final double rasterMs;
  final double totalMs;
  final int endMicros;
  const _Frame({
    required this.buildMs,
    required this.rasterMs,
    required this.totalMs,
    required this.endMicros,
  });
}

/// Immutable rollup the perf panel renders. Value-based so the panel only
/// rebuilds when numbers actually move.
@immutable
class PerfStats {
  final double fps; // effective rate while continuously rendering; 0 = idle
  final int sampleCount; // frames in the rolling window
  // A frame is janky when its *work* on a thread overran the budget. Build and
  // raster run on separate threads (pipelined), so we test each independently —
  // NOT totalSpan, which includes cross-thread latency and over-reports.
  final int uiJankCount; // build (UI thread) overran the budget
  final int rasterJankCount; // raster (GPU thread) overran the budget
  final int jankCount; // frames where UI or raster overran
  final int stallCount; // totalSpan > 100ms — a real perceived hitch
  final double jankRatio; // jankCount / sampleCount
  final double worstBuildMs;
  final double worstRasterMs;
  final double worstTotalMs;
  final double avgBuildMs;
  final double avgRasterMs;
  final List<double> recentTotalsMs; // newest last — for the sparkline

  const PerfStats({
    required this.fps,
    required this.sampleCount,
    required this.uiJankCount,
    required this.rasterJankCount,
    required this.jankCount,
    required this.stallCount,
    required this.jankRatio,
    required this.worstBuildMs,
    required this.worstRasterMs,
    required this.worstTotalMs,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.recentTotalsMs,
  });

  static const empty = PerfStats(
    fps: 0,
    sampleCount: 0,
    uiJankCount: 0,
    rasterJankCount: 0,
    jankCount: 0,
    stallCount: 0,
    jankRatio: 0,
    worstBuildMs: 0,
    worstRasterMs: 0,
    worstTotalMs: 0,
    avgBuildMs: 0,
    avgRasterMs: 0,
    recentTotalsMs: <double>[],
  );

  bool get hasData => sampleCount > 0;

  /// True when there weren't enough back-to-back frames to judge a rate — the
  /// screen was static (event-driven repaints), so FPS is meaningless here.
  bool get isIdle => fps <= 0;

  /// Which thread is the bottleneck — points QA/devs straight at the cause.
  String get bottleneck {
    if (rasterJankCount > uiJankCount && rasterJankCount > 0) {
      return 'GPU / raster (painting)';
    }
    if (uiJankCount > 0) return 'UI thread (build/layout)';
    return '—';
  }

  /// At-a-glance verdict for QA / PM / client. Stalls (real hitches) dominate.
  String get verdict {
    if (!hasData) return 'No data yet';
    if (stallCount > 0) return 'Stalls — investigate';
    if (jankRatio > 0.20) return 'Janky — investigate';
    if (jankRatio > 0.05) return 'Occasional jank';
    return 'Smooth';
  }

  String toReadableText() {
    final b = StringBuffer('PERFORMANCE\n');
    b.writeln('Verdict: $verdict');
    b.writeln('Bottleneck: $bottleneck');
    b.writeln(
      isIdle
          ? 'FPS: idle (static screen — scroll/fling to measure a rate)'
          : 'FPS (while rendering): ${fps.toStringAsFixed(0)}',
    );
    b.writeln('Frames sampled: $sampleCount');
    b.writeln(
      'Dropped frames (work >16.7ms): $jankCount '
      '(${(jankRatio * 100).toStringAsFixed(1)}%) · '
      'UI $uiJankCount / raster $rasterJankCount',
    );
    b.writeln('Stalls (>100ms on screen): $stallCount');
    b.writeln('Worst frame: ${worstTotalMs.toStringAsFixed(1)}ms');
    b.writeln(
      'Avg build/raster: ${avgBuildMs.toStringAsFixed(1)}ms / '
      '${avgRasterMs.toStringAsFixed(1)}ms · '
      'peak ${worstBuildMs.toStringAsFixed(0)} / '
      '${worstRasterMs.toStringAsFixed(0)}ms',
    );
    if (kDebugMode) {
      b.writeln('(Debug build — re-check in profile mode for real numbers.)');
    }
    return b.toString();
  }
}

/// Always-on frame-timing recorder for debug AND profile builds (off in
/// release). Profile mode is where the numbers are real, so capture must run
/// there too. Started once at boot; uses [SchedulerBinding.addTimingsCallback],
/// which the engine batches, so the per-frame cost is just an append to a capped
/// ring buffer. Keeps running while the debug viewer is minimized, so QA can use
/// the app and then reopen the Perf tab to read what just happened.
class PerfMonitor {
  PerfMonitor._();
  static final PerfMonitor instance = PerfMonitor._();

  // ~3s of headroom at 60fps; the window the stats summarise.
  static const int _cap = 180;
  static const double _budgetMs = 16.7; // one 60fps frame
  static const double _stallMs =
      100; // frame on screen >100ms — felt as a hitch
  // Consecutive frames closer than this are "continuous rendering" (a scroll /
  // animation). Bigger gaps mark idle boundaries and are excluded from FPS, so
  // an event-driven screen reads "idle" instead of a misleading low number.
  static const int _activeGapMicros = 100000; // 100ms

  final ListQueue<_Frame> _frames = ListQueue<_Frame>();
  bool _started = false;
  DateTime? _startedAt;

  final ValueNotifier<PerfStats> stats = ValueNotifier<PerfStats>(
    PerfStats.empty,
  );

  DateTime? get startedAt => _startedAt;

  /// Safe to call repeatedly; only the first call wires the callback. Active
  /// only in a development environment — a no-op otherwise.
  void start() {
    if (!DebugTools.enabled || _started) return;
    _started = true;
    _startedAt = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Clears the window so a fresh measurement (e.g. a specific flow) starts now.
  void reset() {
    _frames.clear();
    _startedAt = DateTime.now();
    stats.value = PerfStats.empty;
  }

  void _onTimings(List<FrameTiming> timings) {
    // Dynamic guard: stop doing any work the moment the environment isn't dev.
    if (!DebugTools.enabled) return;
    for (final t in timings) {
      _frames.addLast(
        _Frame(
          buildMs: t.buildDuration.inMicroseconds / 1000.0,
          rasterMs: t.rasterDuration.inMicroseconds / 1000.0,
          totalMs: t.totalSpan.inMicroseconds / 1000.0,
          endMicros: t.timestampInMicroseconds(FramePhase.rasterFinish),
        ),
      );
      while (_frames.length > _cap) {
        _frames.removeFirst();
      }
    }
    stats.value = _compute();
  }

  PerfStats _compute() {
    if (_frames.isEmpty) return PerfStats.empty;
    final n = _frames.length;
    double sumBuild = 0, sumRaster = 0;
    double worstBuild = 0, worstRaster = 0, worstTotal = 0;
    int uiJank = 0, rasterJank = 0, jank = 0, stalls = 0;
    // Effective FPS from gaps between *continuous* frames only.
    double activeIntervalSumMs = 0;
    int activeIntervalCount = 0;
    int? prevEnd;
    final totals = <double>[];

    for (final f in _frames) {
      sumBuild += f.buildMs;
      sumRaster += f.rasterMs;
      if (f.buildMs > worstBuild) worstBuild = f.buildMs;
      if (f.rasterMs > worstRaster) worstRaster = f.rasterMs;
      if (f.totalMs > worstTotal) worstTotal = f.totalMs;
      // Jank = real work overran the budget on either thread (not totalSpan).
      final ui = f.buildMs > _budgetMs;
      final ras = f.rasterMs > _budgetMs;
      if (ui) uiJank++;
      if (ras) rasterJank++;
      if (ui || ras) jank++;
      if (f.totalMs > _stallMs) stalls++;
      if (prevEnd != null) {
        final gap = f.endMicros - prevEnd;
        if (gap > 0 && gap < _activeGapMicros) {
          activeIntervalSumMs += gap / 1000.0;
          activeIntervalCount++;
        }
      }
      prevEnd = f.endMicros;
      totals.add(f.totalMs);
    }

    // Need a few continuous frames to call it a "rate"; else the screen is idle.
    final fps =
        activeIntervalCount >= 5
            ? 1000.0 / (activeIntervalSumMs / activeIntervalCount)
            : 0.0;

    final recent =
        totals.length > 60
            ? totals.sublist(totals.length - 60)
            : List<double>.of(totals);

    return PerfStats(
      fps: fps,
      sampleCount: n,
      uiJankCount: uiJank,
      rasterJankCount: rasterJank,
      jankCount: jank,
      stallCount: stalls,
      jankRatio: jank / n,
      worstBuildMs: worstBuild,
      worstRasterMs: worstRaster,
      worstTotalMs: worstTotal,
      avgBuildMs: sumBuild / n,
      avgRasterMs: sumRaster / n,
      recentTotalsMs: recent,
    );
  }
}
