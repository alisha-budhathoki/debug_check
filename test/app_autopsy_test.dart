import 'package:debug_deck/debug_deck.dart';
import 'package:flutter_test/flutter_test.dart';

DebugLogEntry _api({
  required int id,
  required DebugLogKind kind,
  int? status,
  int ms = 100,
  int? bytes,
  String url = 'https://api.example.com/v1/orders',
  String method = 'GET',
}) {
  return DebugLogEntry(
    id: id,
    timestamp: DateTime(2026, 1, 1, 12, 0, id),
    kind: kind,
    title: '$method $url',
    subtitle: '',
    method: method,
    url: url,
    statusCode: status,
    duration: Duration(milliseconds: ms),
    responseBytes: bytes,
  );
}

DebugLogEntry _error(int id, String msg) => DebugLogEntry(
  id: id,
  timestamp: DateTime(2026, 1, 1, 12, 0, id),
  kind: DebugLogKind.platformError,
  title: 'Uncaught error',
  subtitle: msg,
  errorMessage: msg,
);

void main() {
  final at = DateTime(2026, 1, 1, 12, 0, 0);

  group('AppAutopsy.diagnose', () {
    test('a clean, fast, error-free session grades A', () {
      final entries = [
        _api(id: 1, kind: DebugLogKind.apiSuccess, status: 200, ms: 120),
        _api(id: 2, kind: DebugLogKind.apiSuccess, status: 200, ms: 90),
      ];
      final a = AppAutopsy.diagnose(
        entries: entries,
        perf: PerfStats.empty,
        duplicates: const {},
        now: at,
      );
      expect(a.grade, AutopsyGrade.a);
      expect(a.score, 100);
      expect(a.network.hasData, isTrue);
      expect(a.criticalCount, 0);
      // Reassuring "good" findings so a junior sees green, not an empty list.
      expect(a.findings.any((f) => f.severity == AutopsySeverity.good), isTrue);
    });

    test(
      'server 5xx errors surface as a critical finding and drop the grade',
      () {
        final entries = [
          _api(id: 1, kind: DebugLogKind.apiSuccess, status: 200),
          _api(id: 2, kind: DebugLogKind.apiError, status: 500),
          _api(id: 3, kind: DebugLogKind.apiError, status: 503),
        ];
        final a = AppAutopsy.diagnose(
          entries: entries,
          perf: PerfStats.empty,
          duplicates: const {},
          now: at,
        );
        expect(a.criticalCount, greaterThan(0));
        expect(a.network.score, lessThan(100));
        expect(
          a.grade.index,
          greaterThan(AutopsyGrade.a.index),
        ); // worse than A
        expect(a.findings.first.severity, AutopsySeverity.critical);
      },
    );

    test('rendering stalls produce a critical rendering finding', () {
      const perf = PerfStats(
        fps: 30,
        sampleCount: 60,
        uiJankCount: 10,
        rasterJankCount: 2,
        jankCount: 12,
        stallCount: 3,
        jankRatio: 0.20,
        worstBuildMs: 120,
        worstRasterMs: 20,
        worstTotalMs: 140,
        avgBuildMs: 12,
        avgRasterMs: 6,
        recentTotalsMs: [12, 140, 18],
      );
      final a = AppAutopsy.diagnose(
        entries: const [],
        perf: perf,
        duplicates: const {},
        now: at,
      );
      expect(a.rendering.hasData, isTrue);
      expect(a.rendering.score, lessThan(80));
      expect(
        a.findings.any(
          (f) =>
              f.subsystem == 'Rendering' &&
              f.severity == AutopsySeverity.critical,
        ),
        isTrue,
      );
    });

    test('subsystems with no data are excluded from the overall score', () {
      // No API traffic, no perf frames — only stability (no crashes) is real.
      final a = AppAutopsy.diagnose(
        entries: const [],
        perf: PerfStats.empty,
        duplicates: const {},
        now: at,
      );
      expect(a.network.hasData, isFalse);
      expect(a.rendering.hasData, isFalse);
      expect(a.stability.hasData, isTrue);
      expect(a.score, 100); // judged only on the one subsystem we measured
    });

    test('uncaught errors lower stability and appear in findings', () {
      final a = AppAutopsy.diagnose(
        entries: [_error(1, 'Null check operator used on a null value')],
        perf: PerfStats.empty,
        duplicates: const {},
        now: at,
      );
      expect(a.stability.score, lessThan(100));
      expect(a.findings.any((f) => f.subsystem == 'Stability'), isTrue);
    });

    test('toMarkdown produces a pasteable report with the grade header', () {
      final a = AppAutopsy.diagnose(
        entries: [_api(id: 1, kind: DebugLogKind.apiError, status: 500)],
        perf: PerfStats.empty,
        duplicates: const {},
        now: at,
      );
      final md = a.toMarkdown();
      expect(md, contains('## App Autopsy'));
      expect(md, contains('| Subsystem | Score |'));
      expect(md, contains('Critical'));
    });
  });
}
