import 'package:flutter/foundation.dart';

import '../logging/debug_log_entry.dart';
import '../logging/duplicate_calls.dart';
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
  ///
  /// Duplicate detection runs automatically over [entries]. Pass
  /// [duplicateWindow] to widen or narrow what counts as "the same call fired
  /// twice" (default 5s).
  static AppAutopsy diagnose({
    required List<DebugLogEntry> entries,
    required PerfStats perf,
    Duration duplicateWindow = const Duration(seconds: 5),
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final findings = <AutopsyFinding>[];

    final clusters = findDuplicateCallClusters(
      entries,
      window: duplicateWindow,
    );
    final network = _diagnoseNetwork(entries, clusters.length, findings);
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

    // Weakest measured subsystem — where the health actually leaked. Drives the
    // headline so the verdict points somewhere instead of restating a number.
    final measured =
        [network, rendering, stability].where((s) => s.hasData).toList();
    final weakest =
        measured.isEmpty
            ? null
            : measured.reduce((a, b) => a.score <= b.score ? a : b);

    // Each finder only emits *problems* (a diagnosis + a fix) — never a "looks
    // fine" line, since the subsystem bars already show green. When nothing is
    // wrong, one honest verdict says so rather than three redundant all-clears.
    if (findings.isEmpty) {
      final scope = measured.map((s) => s.name.toLowerCase()).join(', ');
      findings.add(
        AutopsyFinding(
          severity: AutopsySeverity.good,
          subsystem: 'Overall',
          title: 'Nothing to fix',
          detail:
              scope.isEmpty
                  ? 'No traffic, frames or errors captured yet — exercise the app, '
                      'then reopen.'
                  : 'Clean across $scope this session.',
        ),
      );
    }

    // Worst-first. Within a band, insertion order holds, so the most-penalizing
    // finding (added first by each finder) reads as the biggest lever.
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
      headline: _headline(grade, findings, weakest),
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
    // Distinct duplicate *bursts*, not flagged rows. Counting rows scored one
    // triple-fire as three separate problems — a 9-point penalty where the
    // intent was 3.
    int dupeClusters,
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
    final avg =
        durations.isEmpty
            ? 0
            : durations.reduce((a, b) => a + b) ~/ durations.length;
    final slow = completed
        .where((e) => (e.duration?.inMilliseconds ?? 0) > 1000)
        .toList(growable: false);
    final huge = completed
        .where((e) => (e.responseBytes ?? 0) > 512 * 1024)
        .toList(growable: false);
    final server5xx = errors
        .where((e) => (e.statusCode ?? 0) >= 500)
        .toList(growable: false);
    final auth = completed
        .where((e) => e.statusCode == 401 || e.statusCode == 403)
        .toList(growable: false);

    var score = 100.0;
    score -= errorRate * 60; // 50% failures ⇒ −30
    score -= (slow.length / completed.length) * 25;
    score -= (dupeClusters * 3).clamp(0, 15);
    score -= (huge.length * 5).clamp(0, 15);
    if (avg > 800) score -= 8;
    final clamped = score.clamp(0, 100).round();

    // One failure finding, framed by the *dominant* cause — so a wall of
    // failures reads as a single diagnosis ("it's the server" / "it's auth"),
    // not a restated error count you can already see in the API stats.
    if (errors.isNotEmpty) {
      // Lead with the most-severe cause present: a 5xx ("not your fault,
      // escalate") outranks an auth lockout, which outranks generic failures.
      final String title, detail;
      if (server5xx.isNotEmpty) {
        final where = server5xx.map(_label).toSet().take(2).join(', ');
        title = 'Failures are server-side, not in the app';
        detail =
            '${server5xx.length} response(s) came back 5xx ($where). '
            'The client is doing its job — escalate to the backend instead of '
            'chasing it in the app.';
      } else if (auth.isNotEmpty) {
        final where = auth.map(_label).toSet().take(2).join(', ');
        title = 'The app is being locked out (401/403)';
        detail =
            'Requests are rejected before they run ($where). Usually an '
            'expired or missing token — check the auth refresh, not the screen.';
      } else {
        final where = errors.map(_label).toSet().take(2).join(', ');
        title = 'Requests are failing';
        detail =
            '${errors.length} of ${completed.length} calls failed ($where). '
            'Open the failing rows for the exact status and body.';
      }
      out.add(
        AutopsyFinding(
          // A 5xx is a hard failure worth surfacing loudly even if it's rare;
          // otherwise severity scales with how much of the traffic is failing.
          severity:
              server5xx.isNotEmpty || errorRate > 0.25
                  ? AutopsySeverity.critical
                  : AutopsySeverity.warning,
          subsystem: 'Network',
          title: title,
          detail: detail,
        ),
      );
    }
    if (slow.isNotEmpty) {
      final worst = _slowest(slow)!;
      out.add(
        AutopsyFinding(
          severity:
              slow.length > 2 ? AutopsySeverity.warning : AutopsySeverity.info,
          subsystem: 'Network',
          title: 'A few calls dominate the wait',
          detail:
              '${_label(worst)} alone took '
              '${(worst.duration!.inMilliseconds / 1000).toStringAsFixed(1)}s. '
              'Cache it, paginate, or move it off the screen\'s critical path so '
              'the UI isn\'t blocked on it.',
        ),
      );
    }
    if (dupeClusters > 0) {
      out.add(
        const AutopsyFinding(
          severity: AutopsySeverity.warning,
          subsystem: 'Network',
          title: 'The same request is firing more than once',
          detail:
              'Identical calls landed within 5s of each other — a double-tap '
              'or a rebuild loop. Debounce the trigger or guard the in-flight '
              'request so it can\'t fire twice.',
        ),
      );
    }
    if (huge.isNotEmpty) {
      out.add(
        AutopsyFinding(
          severity: AutopsySeverity.info,
          subsystem: 'Network',
          title: 'Some responses are heavy for mobile',
          detail:
              'Over 512KB on ${huge.map(_label).toSet().take(2).join(', ')}. '
              'Paginate or ask the API for gzip / a slimmer shape to cut parse '
              'time and data cost.',
        ),
      );
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

    // The Perf tab already shows the numbers; here we name the cause and the
    // fix. The bottleneck thread points at *which kind* of work to move.
    final onUi = perf.bottleneck.startsWith('UI');
    final fix =
        onUi
            ? 'The UI thread is the bottleneck — move heavy build/layout work '
                '(JSON parsing, big lists, sync I/O) off the main isolate or into '
                'const/cached widgets.'
            : 'The raster thread is the bottleneck — simplify painting: fewer '
                'opacity/clip/shadow layers and RepaintBoundary around the busy '
                'part.';
    if (perf.stallCount > 0) {
      out.add(
        AutopsyFinding(
          severity: AutopsySeverity.critical,
          subsystem: 'Rendering',
          title: 'The UI visibly froze',
          detail:
              'A frame took ${perf.worstTotalMs.toStringAsFixed(0)}ms — long '
              'enough to feel like a hang. $fix',
        ),
      );
    } else if (perf.jankRatio > 0.20) {
      out.add(
        AutopsyFinding(
          severity: AutopsySeverity.warning,
          subsystem: 'Rendering',
          title: 'Scrolling stutters under load',
          detail: 'Roughly one frame in five is missing its budget. $fix',
        ),
      );
    } else if (perf.jankRatio > 0.05) {
      out.add(
        const AutopsyFinding(
          severity: AutopsySeverity.info,
          subsystem: 'Rendering',
          title: 'A little jank creeps in',
          detail:
              'Mostly smooth, with the odd dropped frame. Worth a glance at '
              'the Perf sparkline if a specific screen feels rough.',
        ),
      );
    }

    return SubsystemHealth(name: 'Rendering', score: clamped, hasData: true);
  }

  // ─── Stability ───────────────────────────────────────────────────────────────

  static SubsystemHealth _diagnoseStability(
    List<DebugLogEntry> entries,
    List<AutopsyFinding> out,
  ) {
    final crashes = entries
        .where(
          (e) =>
              e.kind == DebugLogKind.flutterError ||
              e.kind == DebugLogKind.platformError,
        )
        .toList(growable: false);
    // Distinct first-lines approximate distinct root causes.
    final uniqueKinds =
        crashes
            .map((e) => (e.subtitle.isEmpty ? e.title : e.subtitle).trim())
            .toSet();

    if (crashes.isEmpty) {
      // No finding — a clean run is carried by the green Stability bar, not a
      // redundant "all good" line.
      return const SubsystemHealth(
        name: 'Stability',
        score: 100,
        hasData: true,
      );
    }

    final score = (100 - crashes.length * 12).clamp(0, 100);
    final one = uniqueKinds.length == 1;
    out.add(
      AutopsyFinding(
        severity:
            crashes.length > 2
                ? AutopsySeverity.critical
                : AutopsySeverity.warning,
        subsystem: 'Stability',
        title:
            one
                ? 'An exception is escaping unhandled'
                : '${uniqueKinds.length} distinct exceptions escaped unhandled',
        detail:
            'Something threw where nothing caught it — users hit a broken '
            'state, not a handled error. Wrap the risky path in try/catch or an '
            'error boundary; the stack is in the Errors tab.',
      ),
    );
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

  // One sentence that points somewhere: it names the weakest measured subsystem
  // rather than repeating counts the findings and pills already carry.
  static String _headline(
    AutopsyGrade grade,
    List<AutopsyFinding> findings,
    SubsystemHealth? weakest,
  ) {
    final crit =
        findings.where((f) => f.severity == AutopsySeverity.critical).length;
    final warn =
        findings.where((f) => f.severity == AutopsySeverity.warning).length;
    final area = weakest?.name.toLowerCase();
    if (crit > 0) {
      return area == null
          ? '${grade.label} — needs attention now'
          : '${grade.label} — $area is dragging the app down';
    }
    if (warn > 0) {
      return area == null
          ? '${grade.label} — a couple of things to watch'
          : '${grade.label} — solid, but keep an eye on $area';
    }
    return '${grade.label} — nothing needs fixing right now';
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
      b.writeln(
        '| ${s.name} | ${s.hasData ? '${s.score}/100' : 'not measured'} |',
      );
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
