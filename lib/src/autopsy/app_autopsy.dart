import 'package:flutter/foundation.dart';

import '../logging/debug_log_entry.dart';
import '../performance/perf_monitor.dart';

/// Overall letter grade for a diagnosis. Maps 1:1 to a 0–100 score band and a
/// plain-language label, so a junior reads the verdict and a senior reads the
/// number underneath it.
enum AutopsyGrade {
  a('A', 'Excellent'),
  b('B', 'Healthy'),
  c('C', 'Fair'),
  d('D', 'Poor'),
  f('F', 'Critical');

  const AutopsyGrade(this.letter, this.label);
  final String letter;
  final String label;

  static AutopsyGrade fromScore(int score) {
    if (score >= 90) return AutopsyGrade.a;
    if (score >= 80) return AutopsyGrade.b;
    if (score >= 70) return AutopsyGrade.c;
    if (score >= 55) return AutopsyGrade.d;
    return AutopsyGrade.f;
  }
}

/// How loudly a single finding should read. Ordered worst → best so a list of
/// findings sorts by `severity.index`.
enum AutopsySeverity { critical, warning, info, good }

/// One diagnosed observation about the app — the atomic unit of the report.
/// [title] is the headline a junior scans; [detail] is the evidence/number a
/// senior acts on; [subsystem] groups it (Network / Rendering / Stability).
@immutable
class AutopsyFinding {
  final AutopsySeverity severity;
  final String subsystem;
  final String title;
  final String detail;

  const AutopsyFinding({
    required this.severity,
    required this.subsystem,
    required this.title,
    required this.detail,
  });
}

/// A subsystem's health as a 0–100 score plus whether we had any data to judge
/// it. `hasData == false` means "not measured" (e.g. no API traffic yet), which
/// the report renders as a neutral dash rather than a misleading 100.
@immutable
class SubsystemHealth {
  final String name;
  final int score; // 0..100
  final bool hasData;
  const SubsystemHealth({
    required this.name,
    required this.score,
    required this.hasData,
  });
}

/// A full, synthesized diagnosis of the running app — the "autopsy". Combines
/// the network traffic, rendering timings and captured errors the package
/// already records into one graded verdict with prioritized, actionable
/// findings, and a Markdown export ready to paste into a bug report or PR.
///
/// Pure and dependency-light: [diagnose] takes plain data in and returns this
/// value object, so it is trivially unit-testable and does no I/O or rendering.
@immutable
class AppAutopsy {
  final int score; // 0..100 overall
  final AutopsyGrade grade;
  final SubsystemHealth network;
  final SubsystemHealth rendering;
  final SubsystemHealth stability;
  final List<AutopsyFinding> findings;

  /// One-line human verdict, e.g. "Healthy — nothing urgent, one thing to watch".
  final String headline;

  /// Facts the report shows verbatim next to the grade.
  final int apiTotal;
  final int apiErrors;
  final int slowestMs;
  final String? slowestLabel;
  final DateTime generatedAt;

  const AppAutopsy({
    required this.score,
    required this.grade,
    required this.network,
    required this.rendering,
    required this.stability,
    required this.findings,
    required this.headline,
    required this.apiTotal,
    required this.apiErrors,
    required this.slowestMs,
    required this.slowestLabel,
    required this.generatedAt,
  });

  int get criticalCount =>
      findings.where((f) => f.severity == AutopsySeverity.critical).length;
  int get warningCount =>
      findings.where((f) => f.severity == AutopsySeverity.warning).length;

  /// Run the diagnosis. [now] is injectable so the result is deterministic in
  /// tests; production passes `DateTime.now()`.
  static AppAutopsy diagnose({
    required List<DebugLogEntry> entries,
    required PerfStats perf,
    required Map<int, int> duplicates,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final findings = <AutopsyFinding>[];

    final network = _diagnoseNetwork(entries, duplicates, findings);
    final rendering = _diagnoseRendering(perf, findings);
    final stability = _diagnoseStability(entries, findings);

    // Overall = weighted mean over only the subsystems we actually measured, so
    // a static screen with no perf samples isn't scored as if rendering failed.
    const weights = {'Network': 0.40, 'Rendering': 0.35, 'Stability': 0.25};
    double weightedSum = 0, weightUsed = 0;
    for (final s in [network, rendering, stability]) {
      if (!s.hasData) continue;
      final w = weights[s.name]!;
      weightedSum += s.score * w;
      weightUsed += w;
    }
    final overall = weightUsed == 0 ? 100 : (weightedSum / weightUsed).round();
    final grade = AutopsyGrade.fromScore(overall);

    // Sort worst-first, but keep stable ordering within a severity band so the
    // most-penalizing subsystem findings (added first) stay on top.
    findings.sort((a, b) => a.severity.index.compareTo(b.severity.index));

    final api = entries.where((e) => e.isApi).toList(growable: false);
    final errors = api.where((e) => e.kind == DebugLogKind.apiError).length;
    final slowest = _slowest(api);

    return AppAutopsy(
      score: overall,
      grade: grade,
      network: network,
      rendering: rendering,
      stability: stability,
      findings: findings,
      headline: _headline(grade, findings),
      apiTotal: api.length,
      apiErrors: errors,
      slowestMs: slowest?.duration?.inMilliseconds ?? 0,
      slowestLabel: slowest == null ? null : _label(slowest),
      generatedAt: at,
    );
  }

  // ─── Network ───────────────────────────────────────────────────────────────

  static SubsystemHealth _diagnoseNetwork(
    List<DebugLogEntry> entries,
    Map<int, int> duplicates,
    List<AutopsyFinding> out,
  ) {
    final api = entries.where((e) => e.isApi).toList(growable: false);
    final completed = api
        .where((e) => e.kind != DebugLogKind.apiInFlight)
        .toList(growable: false);
    if (completed.isEmpty) {
      return const SubsystemHealth(name: 'Network', score: 100, hasData: false);
    }

    final errors =
        completed.where((e) => e.kind == DebugLogKind.apiError).toList();
    final errorRate = errors.length / completed.length;
    final durations = completed
        .where((e) => e.duration != null)
        .map((e) => e.duration!.inMilliseconds)
        .toList(growable: false);
    final avg = durations.isEmpty
        ? 0
        : durations.reduce((a, b) => a + b) ~/ durations.length;
    final slow = completed
        .where((e) => (e.duration?.inMilliseconds ?? 0) > 1000)
        .toList(growable: false);
    final huge = completed
        .where((e) => (e.responseBytes ?? 0) > 512 * 1024)
        .toList(growable: false);
    // Duplicate *clusters* (distinct groups), not individual flagged rows.
    final dupeRows = api.where((e) => duplicates.containsKey(e.id)).length;
    final server5xx = errors
        .where((e) => (e.statusCode ?? 0) >= 500)
        .toList(growable: false);
    final auth = completed
        .where((e) => e.statusCode == 401 || e.statusCode == 403)
        .toList(growable: false);

    var score = 100.0;
    score -= errorRate * 60; // 50% failures ⇒ −30
    score -= (slow.length / completed.length) * 25;
    score -= (dupeRows * 3).clamp(0, 15);
    score -= (huge.length * 5).clamp(0, 15);
    if (avg > 800) score -= 8;
    final clamped = score.clamp(0, 100).round();

    // Findings — worst offenders first, then reassurance when clean.
    if (server5xx.isNotEmpty) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.critical,
        subsystem: 'Network',
        title: '${server5xx.length} server error'
            '${server5xx.length == 1 ? '' : 's'} (5xx)',
        detail: server5xx.map(_label).toSet().take(3).join(', '),
      ));
    }
    if (errors.isNotEmpty) {
      out.add(AutopsyFinding(
        severity: errorRate > 0.25
            ? AutopsySeverity.critical
            : AutopsySeverity.warning,
        subsystem: 'Network',
        title: '${errors.length} of ${completed.length} requests failed '
            '(${(errorRate * 100).toStringAsFixed(0)}%)',
        detail: errors.map(_label).toSet().take(3).join(', '),
      ));
    }
    if (auth.isNotEmpty) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.warning,
        subsystem: 'Network',
        title: '${auth.length} auth rejection'
            '${auth.length == 1 ? '' : 's'} (401/403)',
        detail: 'Token/permission problem: ${auth.map(_label).toSet().take(2).join(', ')}',
      ));
    }
    if (slow.isNotEmpty) {
      final worst = _slowest(slow)!;
      out.add(AutopsyFinding(
        severity: slow.length > 2 ? AutopsySeverity.warning : AutopsySeverity.info,
        subsystem: 'Network',
        title: '${slow.length} slow call'
            '${slow.length == 1 ? '' : 's'} over 1s',
        detail: 'Worst ${worst.duration!.inMilliseconds}ms · ${_label(worst)}',
      ));
    }
    if (dupeRows > 0) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.warning,
        subsystem: 'Network',
        title: '$dupeRows duplicate request${dupeRows == 1 ? '' : 's'}',
        detail: 'Identical calls within 5s — likely a double-tap or rebuild loop',
      ));
    }
    if (huge.isNotEmpty) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.info,
        subsystem: 'Network',
        title: '${huge.length} oversized payload'
            '${huge.length == 1 ? '' : 's'} (>512KB)',
        detail: 'Consider pagination/compression: ${huge.map(_label).toSet().take(2).join(', ')}',
      ));
    }
    if (errors.isEmpty && slow.isEmpty && dupeRows == 0) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.good,
        subsystem: 'Network',
        title: 'Network clean',
        detail: '${completed.length} requests, no failures, avg ${avg}ms',
      ));
    }

    return SubsystemHealth(name: 'Network', score: clamped, hasData: true);
  }

  // ─── Rendering ───────────────────────────────────────────────────────────────

  static SubsystemHealth _diagnoseRendering(
    PerfStats perf,
    List<AutopsyFinding> out,
  ) {
    if (!perf.hasData) {
      return const SubsystemHealth(
        name: 'Rendering',
        score: 100,
        hasData: false,
      );
    }

    var score = 100.0;
    score -= perf.jankRatio * 120; // 25% dropped ⇒ −30
    score -= (perf.stallCount * 8).clamp(0, 30);
    if (perf.worstTotalMs > 100) score -= 10;
    final clamped = score.clamp(0, 100).round();

    if (perf.stallCount > 0) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.critical,
        subsystem: 'Rendering',
        title: '${perf.stallCount} stall'
            '${perf.stallCount == 1 ? '' : 's'} over 100ms',
        detail: 'Worst frame ${perf.worstTotalMs.toStringAsFixed(0)}ms · '
            'bottleneck ${perf.bottleneck}',
      ));
    } else if (perf.jankRatio > 0.20) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.warning,
        subsystem: 'Rendering',
        title: '${(perf.jankRatio * 100).toStringAsFixed(0)}% of frames dropped',
        detail: 'UI ${perf.uiJankCount} · raster ${perf.rasterJankCount} · '
            'bottleneck ${perf.bottleneck}',
      ));
    } else if (perf.jankRatio > 0.05) {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.info,
        subsystem: 'Rendering',
        title: 'Occasional jank '
            '(${(perf.jankRatio * 100).toStringAsFixed(0)}% of frames)',
        detail: 'Mostly smooth; worst frame '
            '${perf.worstTotalMs.toStringAsFixed(0)}ms',
      ));
    } else {
      out.add(AutopsyFinding(
        severity: AutopsySeverity.good,
        subsystem: 'Rendering',
        title: 'Rendering smooth',
        detail: '${perf.sampleCount} frames, '
            '${(perf.jankRatio * 100).toStringAsFixed(0)}% dropped'
            '${perf.isIdle ? '' : ', ${perf.fps.toStringAsFixed(0)} fps'}',
      ));
    }

    return SubsystemHealth(name: 'Rendering', score: clamped, hasData: true);
  }

  // ─── Stability ───────────────────────────────────────────────────────────────

  static SubsystemHealth _diagnoseStability(
    List<DebugLogEntry> entries,
    List<AutopsyFinding> out,
  ) {
    final crashes = entries
        .where((e) =>
            e.kind == DebugLogKind.flutterError ||
            e.kind == DebugLogKind.platformError)
        .toList(growable: false);
    // Distinct first-lines approximate distinct root causes.
    final uniqueKinds = crashes
        .map((e) => (e.subtitle.isEmpty ? e.title : e.subtitle).trim())
        .toSet();

    if (crashes.isEmpty) {
      out.add(const AutopsyFinding(
        severity: AutopsySeverity.good,
        subsystem: 'Stability',
        title: 'No uncaught errors',
        detail: 'No Flutter or platform exceptions captured this session',
      ));
      return const SubsystemHealth(
        name: 'Stability',
        score: 100,
        hasData: true,
      );
    }

    final score = (100 - crashes.length * 12).clamp(0, 100);
    out.add(AutopsyFinding(
      severity:
          crashes.length > 2 ? AutopsySeverity.critical : AutopsySeverity.warning,
      subsystem: 'Stability',
      title: '${crashes.length} uncaught error'
          '${crashes.length == 1 ? '' : 's'} '
          '(${uniqueKinds.length} distinct)',
      detail: uniqueKinds.take(2).join(' · '),
    ));
    return SubsystemHealth(name: 'Stability', score: score, hasData: true);
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  static DebugLogEntry? _slowest(List<DebugLogEntry> api) {
    DebugLogEntry? best;
    var bestMs = -1;
    for (final e in api) {
      final ms = e.duration?.inMilliseconds ?? -1;
      if (ms > bestMs) {
        bestMs = ms;
        best = e;
      }
    }
    return bestMs < 0 ? null : best;
  }

  static String _label(DebugLogEntry e) {
    final method = e.method ?? '?';
    final url = e.url;
    if (url == null) return method;
    final u = Uri.tryParse(url);
    final path = (u == null || u.path.isEmpty) ? url : u.path;
    return '$method $path';
  }

  static String _headline(AutopsyGrade grade, List<AutopsyFinding> findings) {
    final crit =
        findings.where((f) => f.severity == AutopsySeverity.critical).length;
    final warn =
        findings.where((f) => f.severity == AutopsySeverity.warning).length;
    if (crit > 0) {
      return '${grade.label} — $crit critical issue${crit == 1 ? '' : 's'} '
          'need attention';
    }
    if (warn > 0) {
      return '${grade.label} — nothing urgent, '
          '$warn thing${warn == 1 ? '' : 's'} to watch';
    }
    return '${grade.label} — no issues detected';
  }

  /// Paste-ready Markdown for a bug report, PR description or ticket. Groups the
  /// findings by severity under a header carrying the grade and key numbers.
  String toMarkdown() {
    final b = StringBuffer();
    b.writeln('## App Autopsy — ${grade.letter} · ${grade.label} ($score/100)');
    b.writeln();
    b.writeln('_${headline}_');
    b.writeln();
    b.writeln('| Subsystem | Score |');
    b.writeln('| --- | --- |');
    for (final s in [network, rendering, stability]) {
      b.writeln('| ${s.name} | ${s.hasData ? '${s.score}/100' : 'not measured'} |');
    }
    b.writeln();
    b.writeln('- Requests: $apiTotal ($apiErrors failed)');
    if (slowestLabel != null) {
      b.writeln('- Slowest: ${slowestMs}ms · $slowestLabel');
    }
    b.writeln('- Generated: ${generatedAt.toIso8601String()}');
    b.writeln();

    void section(String title, AutopsySeverity sev) {
      final items = findings.where((f) => f.severity == sev).toList();
      if (items.isEmpty) return;
      b.writeln('### $title');
      for (final f in items) {
        b.writeln('- **${f.title}** — ${f.detail} _(${f.subsystem})_');
      }
      b.writeln();
    }

    section('🔴 Critical', AutopsySeverity.critical);
    section('🟡 Warnings', AutopsySeverity.warning);
    section('🔵 Notes', AutopsySeverity.info);
    section('🟢 Healthy', AutopsySeverity.good);
    return b.toString().trimRight();
  }
}
