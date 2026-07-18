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
      // Distinct endpoints. Two identical GETs a second apart would be a
      // genuine duplicate-call finding, so reusing the default URL here would
      // mean the "clean session" fixture wasn't actually clean.
      final entries = [
        _api(id: 1, kind: DebugLogKind.apiSuccess, status: 200, ms: 120),
        _api(
          id: 2,
          kind: DebugLogKind.apiSuccess,
          status: 200,
          ms: 90,
          url: 'https://api.example.com/v1/profile',
        ),
      ];
      final a = AppAutopsy.diagnose(
        entries: entries,
        perf: PerfStats.empty,
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
      final a = AppAutopsy.diagnose(entries: const [], perf: perf, now: at);
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
        now: at,
      );
      expect(a.stability.score, lessThan(100));
      expect(a.findings.any((f) => f.subsystem == 'Stability'), isTrue);
    });

    test('toMarkdown produces a pasteable report with the grade header', () {
      final a = AppAutopsy.diagnose(
        entries: [_api(id: 1, kind: DebugLogKind.apiError, status: 500)],
        perf: PerfStats.empty,
        now: at,
      );
      final md = a.toMarkdown();
      expect(md, contains('## App Autopsy'));
      expect(md, contains('| Subsystem | Score |'));
      expect(md, contains('Critical'));
    });
  });

  group('duplicate detection feeds the network score', () {
    List<DebugLogEntry> burst(int n, {int startSecond = 1}) => [
      for (var i = 0; i < n; i++)
        _api(
          id: startSecond + i,
          kind: DebugLogKind.apiSuccess,
          status: 200,
          ms: 50,
        ),
    ];

    test('one burst of three counts once, not three times', () {
      // Rows-vs-clusters: the old code counted 3 flagged rows for a single
      // triple-fire and applied a 9-point penalty where 3 was intended.
      final a = AppAutopsy.diagnose(
        entries: burst(3),
        perf: PerfStats.empty,
        now: at,
      );
      expect(findDuplicateCallClusters(burst(3)).length, 1);
      // The penalty lands on the network subsystem; the overall is a weighted
      // mean across network + stability, so assert the number under test.
      expect(a.network.score, 97, reason: '100 - (1 cluster * 3)');
    });

    test('two separate bursts count twice', () {
      final entries = [
        ...burst(2, startSecond: 1),
        // Far enough apart to break the 5s run, so this is a second burst.
        ...burst(2, startSecond: 40),
      ];
      expect(findDuplicateCallClusters(entries).length, 2);
      final a = AppAutopsy.diagnose(
        entries: entries,
        perf: PerfStats.empty,
        now: at,
      );
      expect(a.network.score, 94, reason: '100 - (2 clusters * 3)');
    });

    test('calls to distinct endpoints are not duplicates', () {
      final entries = [
        _api(id: 1, kind: DebugLogKind.apiSuccess, status: 200),
        _api(
          id: 2,
          kind: DebugLogKind.apiSuccess,
          status: 200,
          url: 'https://api.example.com/v1/profile',
        ),
      ];
      expect(findDuplicateCallClusters(entries), isEmpty);
      expect(
        AppAutopsy.diagnose(
          entries: entries,
          perf: PerfStats.empty,
          now: at,
        ).network.score,
        100,
      );
    });

    test('findDuplicateApiCalls is reachable from outside the package', () {
      // The README documented calling diagnose() directly, but the map it
      // required came from a function trapped in a part file.
      expect(findDuplicateApiCalls(burst(3)).length, 3);
      expect(findDuplicateApiCalls(burst(3)).values, everyElement(3));
    });
  });
}
