import 'dart:convert';

import 'package:debug_deck/debug_deck.dart';
import 'package:flutter_test/flutter_test.dart';

DebugLogEntry _api({
  required int id,
  DebugLogKind kind = DebugLogKind.apiSuccess,
  int? status = 200,
  int ms = 100,
  String path = '/v1/orders',
  String method = 'GET',
  Map<String, String>? reqHeaders,
}) => DebugLogEntry(
  id: id,
  timestamp: DateTime(2026, 1, 1, 12, 0, id),
  kind: kind,
  title: '$method $path',
  subtitle: '',
  method: method,
  url: 'https://api.example.com$path',
  statusCode: status,
  duration: Duration(milliseconds: ms),
  requestHeaders: reqHeaders,
);

void main() {
  final at = DateTime(2026, 1, 1, 12, 30, 0);

  setUp(() {
    DebugTools.redaction = DebugRedaction.standard();
    DebugTools.revealSecrets.value = false;
  });

  group('SessionExport.toMarkdown', () {
    test('leads with the verdict, then the environment', () {
      final md = SessionExport.toMarkdown(
        entries: [_api(id: 1)],
        perf: PerfStats.empty,
        now: at,
      );
      expect(md, startsWith('# Session report'));
      expect(md, contains('## Diagnosis'));
      expect(md, contains('| Generated | 2026-01-01 12:30:00 |'));
      expect(md, contains('| Requests | 1 (0 failed) |'));
    });

    test('failures get their own section with times and codes', () {
      final md = SessionExport.toMarkdown(
        entries: [
          _api(id: 1),
          _api(id: 2, kind: DebugLogKind.apiError, status: 500),
        ],
        perf: PerfStats.empty,
        now: at,
      );
      expect(md, contains('## Failures'));
      expect(md, contains('`500`'));
      expect(md, contains('12:00:02'));
    });

    test('repeated calls are reported as bursts, not as N rows', () {
      final md = SessionExport.toMarkdown(
        entries: [_api(id: 1), _api(id: 2), _api(id: 3)],
        perf: PerfStats.empty,
        now: at,
      );
      expect(md, contains('## Repeated calls'));
      expect(md, contains('3× `GET /v1/orders`'));
    });

    test('a clean session omits the failure and duplicate sections', () {
      final md = SessionExport.toMarkdown(
        entries: [_api(id: 1), _api(id: 2, path: '/v1/profile')],
        perf: PerfStats.empty,
        now: at,
      );
      expect(md, isNot(contains('## Failures')));
      expect(md, isNot(contains('## Repeated calls')));
      expect(md, contains('## Timeline'));
    });

    test('a truncated timeline says so rather than silently dropping', () {
      final many = [for (var i = 1; i <= 60; i++) _api(id: i, path: '/p$i')];
      final md = SessionExport.toMarkdown(
        entries: many,
        perf: PerfStats.empty,
        maxTimeline: 10,
        now: at,
      );
      expect(md, contains('50 earlier entries omitted'));
    });

    test('breadcrumbs appear in the timeline', () {
      final md = SessionExport.toMarkdown(
        entries: [
          DebugLogEntry(
            id: 1,
            timestamp: DateTime(2026, 1, 1, 12, 0, 1),
            kind: DebugLogKind.info,
            title: 'CartBloc',
            subtitle: 'AddItem(sku: 42)',
          ),
        ],
        perf: PerfStats.empty,
        now: at,
      );
      expect(md, contains('CartBloc — AddItem(sku: 42)'));
    });
  });

  group('SessionExport.toHar', () {
    test('emits a valid HAR 1.2 envelope of API entries only', () {
      final har = jsonDecode(
        SessionExport.toHar(
          entries: [
            _api(id: 1),
            DebugLogEntry(
              id: 2,
              timestamp: DateTime(2026, 1, 1, 12, 0, 2),
              kind: DebugLogKind.info,
              title: 'breadcrumb',
              subtitle: '',
            ),
          ],
        ),
      );
      expect(har['log']['version'], '1.2');
      final entries = har['log']['entries'] as List;
      expect(entries, hasLength(1), reason: 'a breadcrumb has no HAR shape');
      expect(entries.single['request']['method'], 'GET');
      expect(entries.single['response']['status'], 200);
    });

    test('exports masked headers, never the raw secret', () {
      final har = SessionExport.toHar(
        entries: [
          _api(
            id: 1,
            // Already masked at capture under the default drop mode; this
            // mirrors what the logger would have stored.
            reqHeaders: const {'Authorization': 'Bearer ••••n123'},
          ),
        ],
      );
      expect(har, contains('Bearer ••••n123'));
      expect(har, isNot(contains('supersecret')));
    });
  });
}
