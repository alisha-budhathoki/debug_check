import 'package:debug_deck/debug_deck.dart';
import 'package:flutter_test/flutter_test.dart';

DebugLogEntry _api({
  required int id,
  DebugLogKind kind = DebugLogKind.apiSuccess,
  int? status = 200,
  String method = 'GET',
  bool pinned = false,
}) => DebugLogEntry(
  id: id,
  timestamp: DateTime(2026, 1, 1, 12, 0, id),
  kind: kind,
  title: '$method /x$id',
  subtitle: '',
  method: method,
  url: 'https://api.example.com/x$id',
  statusCode: status,
  pinned: pinned,
);

DebugLogEntry _event(int id, {bool pinned = false}) => DebugLogEntry(
  id: id,
  timestamp: DateTime(2026, 1, 1, 12, 0, id),
  kind: DebugLogKind.info,
  title: 'CartBloc',
  subtitle: 'AddItem(sku: 42)',
  pinned: pinned,
);

DebugLogEntry _crash(int id) => DebugLogEntry(
  id: id,
  timestamp: DateTime(2026, 1, 1, 12, 0, id),
  kind: DebugLogKind.platformError,
  title: 'Uncaught',
  subtitle: 'boom',
  errorMessage: 'boom',
);

void main() {
  group('LogCategory', () {
    test('events are breadcrumbs — the case that had no filter before', () {
      final e = _event(1);
      expect(LogCategory.event.matches(e), isTrue);
      expect(LogCategory.api.matches(e), isFalse);
      expect(LogCategory.error.matches(e), isFalse);
    });

    test('a failed API call is an error, not an api row', () {
      final e = _api(id: 1, kind: DebugLogKind.apiError, status: 500);
      expect(LogCategory.error.matches(e), isTrue);
      expect(
        LogCategory.api.matches(e),
        isFalse,
        reason: 'otherwise API and Errors would both list it, double-counting',
      );
    });
  });

  group('StatusClass', () {
    test('bands match by range', () {
      expect(StatusClass.success.matches(_api(id: 1, status: 204)), isTrue);
      expect(StatusClass.clientError.matches(_api(id: 1, status: 404)), isTrue);
      expect(StatusClass.serverError.matches(_api(id: 1, status: 503)), isTrue);
      expect(StatusClass.success.matches(_api(id: 1, status: 404)), isFalse);
    });

    test('a transport failure has no code and gets its own band', () {
      final failed = _api(id: 1, kind: DebugLogKind.apiError, status: null);
      expect(StatusClass.failed.matches(failed), isTrue);
      expect(StatusClass.serverError.matches(failed), isFalse);
    });

    test('an in-flight call is not yet a failure', () {
      final pending = _api(id: 1, kind: DebugLogKind.apiInFlight, status: null);
      expect(StatusClass.failed.matches(pending), isFalse);
    });
  });

  group('LogFilter', () {
    test('a default filter constrains nothing', () {
      expect(LogFilter.none.isEmpty, isTrue);
      expect(LogFilter.none.activeCount, 0);
      expect(LogFilter.none.matches(_event(1)), isTrue);
      expect(LogFilter.none.matches(_api(id: 2)), isTrue);
    });

    test('activeCount counts axes, not values', () {
      const f = LogFilter(methods: {'GET', 'POST', 'PUT'});
      expect(f.activeCount, 1, reason: 'three methods is one active filter');
      const g = LogFilter(methods: {'GET'}, pinnedOnly: true);
      expect(g.activeCount, 2);
    });

    test('status filters drop non-API rows entirely', () {
      const f = LogFilter(statusClasses: {StatusClass.serverError});
      expect(f.matches(_api(id: 1, status: 500)), isTrue);
      expect(f.matches(_api(id: 2, status: 200)), isFalse);
      // A breadcrumb has no status; asking "show me 5xx" is a question about
      // traffic, so unrelated rows shouldn't ride along.
      expect(f.matches(_event(3)), isFalse);
      expect(f.matches(_crash(4)), isFalse);
    });

    test('method filter is case-insensitive on the entry side', () {
      const f = LogFilter(methods: {'POST'});
      expect(f.matches(_api(id: 1, method: 'post')), isTrue);
      expect(f.matches(_api(id: 2, method: 'GET')), isFalse);
    });

    test('axes combine with AND', () {
      const f = LogFilter(
        methods: {'GET'},
        statusClasses: {StatusClass.clientError},
      );
      expect(f.matches(_api(id: 1, method: 'GET', status: 404)), isTrue);
      expect(f.matches(_api(id: 2, method: 'GET', status: 200)), isFalse);
      expect(f.matches(_api(id: 3, method: 'POST', status: 404)), isFalse);
    });

    test('pinnedOnly keeps just the pinned rows', () {
      const f = LogFilter(pinnedOnly: true);
      expect(f.matches(_api(id: 1, pinned: true)), isTrue);
      expect(f.matches(_api(id: 2)), isFalse);
      expect(f.matches(_event(3, pinned: true)), isTrue);
    });

    test('methodsIn offers only what the session contains', () {
      final entries = [
        _api(id: 1, method: 'GET'),
        _api(id: 2, method: 'post'),
        _api(id: 3, method: 'GET'),
        _event(4),
      ];
      expect(LogFilter.methodsIn(entries), ['GET', 'POST']);
    });
  });

  group('pinning survives eviction', () {
    setUp(() {
      DebugTools.setEnabled(true);
      DebugLogger.instance.clear();
    });

    Future<List<DebugLogEntry>> flushed() async {
      await Future<void>.delayed(Duration.zero);
      return DebugLogger.instance.entries.value;
    }

    test('a pinned entry outlives 200 newer ones', () async {
      DebugLogger.instance.logInfo('keep me');
      final first = (await flushed()).single;
      expect(DebugLogger.instance.togglePin(first.id), isTrue);

      // Overflow the 200-entry ring buffer several times over.
      for (var i = 0; i < 260; i++) {
        DebugLogger.instance.logInfo('noise $i');
      }
      final after = await flushed();
      expect(
        after.any((e) => e.title == 'keep me' && e.pinned),
        isTrue,
        reason: 'pinning is pointless if the buffer evicts the pin anyway',
      );
      expect(after.any((e) => e.title == 'noise 0'), isFalse);
    });

    test('togglePin flips back and reports the new state', () async {
      DebugLogger.instance.logInfo('x');
      final e = (await flushed()).single;
      expect(DebugLogger.instance.togglePin(e.id), isTrue);
      expect(DebugLogger.instance.togglePin(e.id), isFalse);
      expect((await flushed()).single.pinned, isFalse);
    });

    test('togglePin reports null for an unknown id', () {
      expect(DebugLogger.instance.togglePin(999999), isNull);
    });

    test('clearUnpinned keeps pins, clear wipes everything', () async {
      DebugLogger.instance.logInfo('keep');
      DebugLogger.instance.logInfo('drop');
      final all = await flushed();
      DebugLogger.instance.togglePin(
        all.firstWhere((e) => e.title == 'keep').id,
      );

      DebugLogger.instance.clearUnpinned();
      final kept = await flushed();
      expect(kept.map((e) => e.title), ['keep']);

      DebugLogger.instance.clear();
      expect(await flushed(), isEmpty);
    });
  });
}
