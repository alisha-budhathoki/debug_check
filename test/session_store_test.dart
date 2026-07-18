import 'package:debug_deck/debug_deck.dart';
import 'package:flutter_test/flutter_test.dart';

DebugLogEntry _entry(int id, {bool pinned = false}) => DebugLogEntry(
  id: id,
  timestamp: DateTime(2026, 1, 1, 12, 0, id % 60),
  kind: DebugLogKind.apiSuccess,
  title: 'GET /v$id',
  subtitle: 'ok',
  method: 'GET',
  url: 'https://api.example.com/v$id',
  statusCode: 200,
  duration: const Duration(milliseconds: 42),
  requestHeaders: const {'Accept': 'application/json'},
  responseBody: '{"ok":true}',
  responseBytes: 11,
  pinned: pinned,
);

Future<List<DebugLogEntry>> _flushed() async {
  await Future<void>.delayed(Duration.zero);
  return DebugLogger.instance.entries.value;
}

void main() {
  final store = SessionStore.instance;

  setUp(() async {
    DebugTools.setEnabled(true);
    DebugTools.persistSession = false;
    DebugLogger.instance.clear();
    await store.clear();
  });

  tearDown(() async {
    DebugTools.persistSession = false;
    await store.clear();
  });

  test('save then restore round-trips every field', () async {
    await store.save([_entry(1, pinned: true)]);
    final restored = await store.restore();
    expect(restored, hasLength(1));

    final e = restored.single;
    expect(e.id, 1);
    expect(e.kind, DebugLogKind.apiSuccess);
    expect(e.method, 'GET');
    expect(e.url, 'https://api.example.com/v1');
    expect(e.statusCode, 200);
    expect(e.duration, const Duration(milliseconds: 42));
    expect(e.requestHeaders, {'Accept': 'application/json'});
    expect(e.responseBody, '{"ok":true}');
    expect(e.responseBytes, 11);
    expect(e.pinned, isTrue);
    expect(e.timestamp, DateTime(2026, 1, 1, 12, 0, 1));
  });

  test('only the newest maxPersisted entries are written', () async {
    final many = [for (var i = 1; i <= 100; i++) _entry(i)];
    await store.save(many);
    final restored = await store.restore();
    expect(restored, hasLength(SessionStore.maxPersisted));
    // Newest-first ordering means the head of the list is what's kept.
    expect(restored.first.id, 1);
  });

  test('restore is empty when nothing was saved', () async {
    expect(await store.restore(), isEmpty);
  });

  test('restoring adopts the entries and then drops the file', () async {
    await store.save([_entry(7)]);

    final count = await DebugLogger.instance.restorePreviousSession();
    expect(count, 1);
    expect((await _flushed()).map((e) => e.id), contains(7));

    // Second launch must not resurrect the same entries.
    expect(
      await store.restore(),
      isEmpty,
      reason: 'the file is consumed on restore',
    );
  });

  test('restored ids do not collide with this run', () async {
    await store.save([_entry(500)]);
    await DebugLogger.instance.restorePreviousSession();

    DebugLogger.instance.logInfo('new entry');
    final all = await _flushed();
    final ids = all.map((e) => e.id).toList();
    expect(
      ids.toSet(),
      hasLength(ids.length),
      reason: 'a duplicate id would break pin/remove, which address by id',
    );
  });

  test('restored entries sit behind this run in the list', () async {
    await store.save([_entry(3)]);
    DebugLogger.instance.logInfo('current run');
    await DebugLogger.instance.restorePreviousSession();

    final all = await _flushed();
    expect(all.first.title, 'current run');
    expect(all.last.id, 3, reason: 'older session goes to the tail');
  });

  test(
    'persistSession off means no write',
    () async {
      DebugTools.persistSession = false;
      DebugLogger.instance.logInfo('not persisted');
      await _flushed();
      // Debounce is 2s; well past it, nothing should exist.
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(await store.restore(), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
