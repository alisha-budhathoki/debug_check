/// Carries a session across a restart.
///
/// A crash is exactly when the log matters most and exactly when it is lost:
/// the buffer lives in memory, so the run that died takes its own evidence
/// with it. This writes the tail of the session to disk so the *next* launch
/// can show what the previous one was doing.
///
/// Opt-in via `DebugTools.init(persistSession: true)`. Off by default because
/// it writes request and response bodies to disk, which is a decision the app
/// should make knowingly rather than inherit.
library;

import 'dart:async';
import 'dart:convert';

import '../logging/debug_log_entry.dart';

import 'log_store_stub.dart' if (dart.library.io) 'log_store_io.dart';

/// Reads and writes the previous session's tail.
class SessionStore {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  static const _fileName = 'last_session.json';

  /// How many entries are carried across. The full 200 with bodies can run to
  /// megabytes; the tail is where a crash lives, and a bounded write keeps the
  /// save cheap enough to run on a debounce.
  static const int maxPersisted = 60;

  /// Schema tag. A format change bumps this and old files are discarded rather
  /// than parsed into something wrong.
  static const int _version = 1;

  bool get supported => sessionStorageSupported;

  Timer? _debounce;

  /// Restores the previous run's entries, newest first, or an empty list.
  ///
  /// Always returns — a missing, corrupt, or newer-schema file is treated as
  /// "no previous session". Diagnostics must not be able to break startup.
  Future<List<DebugLogEntry>> restore() async {
    final raw = await readSessionFile(_fileName);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      if (decoded['version'] != _version) return const [];
      final list = decoded['entries'];
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .nonNulls
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Persists the newest [maxPersisted] entries, coalescing rapid calls.
  ///
  /// Debounced because it is driven by the log notifier, which ticks on every
  /// completed request — writing the file per request would turn a debug tool
  /// into an I/O source that distorts the very timings it measures.
  void scheduleSave(List<DebugLogEntry> entries) {
    if (!supported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => save(entries));
  }

  Future<void> save(List<DebugLogEntry> entries) async {
    if (!supported) return;
    final slice =
        entries.length > maxPersisted
            ? entries.sublist(0, maxPersisted)
            : entries;
    final payload = jsonEncode({
      'version': _version,
      'savedAt': DateTime.now().toIso8601String(),
      'entries': slice.map(_toJson).toList(growable: false),
    });
    await writeSessionFile(_fileName, payload);
  }

  /// Drops the stored session. Called after a successful restore so the same
  /// entries can't reappear on a third launch, long after they're relevant.
  Future<void> clear() async {
    _debounce?.cancel();
    await deleteSessionFile(_fileName);
  }

  // ── (de)serialization ──

  static Map<String, dynamic> _toJson(DebugLogEntry e) => {
    'id': e.id,
    'ts': e.timestamp.toIso8601String(),
    'kind': e.kind.name,
    'title': e.title,
    'subtitle': e.subtitle,
    if (e.method != null) 'method': e.method,
    if (e.url != null) 'url': e.url,
    if (e.statusCode != null) 'status': e.statusCode,
    if (e.duration != null) 'durMs': e.duration!.inMilliseconds,
    if (e.queryParameters != null) 'query': e.queryParameters,
    if (e.requestHeaders != null) 'reqHeaders': e.requestHeaders,
    if (e.responseHeaders != null) 'resHeaders': e.responseHeaders,
    if (e.requestBody != null) 'reqBody': e.requestBody,
    if (e.responseBody != null) 'resBody': e.responseBody,
    if (e.responseBytes != null) 'bytes': e.responseBytes,
    if (e.errorMessage != null) 'error': e.errorMessage,
    if (e.stackTrace != null) 'stack': e.stackTrace,
    if (e.pinned) 'pinned': true,
  };

  /// Returns null for a row that can't be rebuilt, so one bad entry costs one
  /// entry rather than the whole restore.
  static DebugLogEntry? _fromJson(Map<String, dynamic> j) {
    try {
      final kindName = j['kind'] as String?;
      final kind = DebugLogKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => DebugLogKind.info,
      );
      final ts = DateTime.tryParse(j['ts'] as String? ?? '');
      if (ts == null) return null;
      return DebugLogEntry(
        id: j['id'] as int? ?? 0,
        timestamp: ts,
        kind: kind,
        title: j['title'] as String? ?? '(restored)',
        subtitle: j['subtitle'] as String? ?? '',
        method: j['method'] as String?,
        url: j['url'] as String?,
        statusCode: j['status'] as int?,
        duration:
            j['durMs'] is int
                ? Duration(milliseconds: j['durMs'] as int)
                : null,
        queryParameters: _strMap(j['query']),
        requestHeaders: _strMap(j['reqHeaders']),
        responseHeaders: _strMap(j['resHeaders']),
        requestBody: j['reqBody'] as String?,
        responseBody: j['resBody'] as String?,
        responseBytes: j['bytes'] as int?,
        errorMessage: j['error'] as String?,
        stackTrace: j['stack'] as String?,
        pinned: j['pinned'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, String>? _strMap(dynamic v) {
    if (v is! Map) return null;
    return v.map((k, value) => MapEntry('$k', '$value'));
  }
}
