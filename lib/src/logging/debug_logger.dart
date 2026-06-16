import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:debug_deck/debug_deck.dart';

/// Immutable counts snapshot. Equality is value-based, so the chip's
/// [ValueListenableBuilder] skips rebuilds when neither total nor errors
/// changed (e.g. when an in-flight API entry is replaced with its success).
@immutable
class DebugLogCounts {
  final int total;
  final int errors;
  const DebugLogCounts({required this.total, required this.errors});

  static const empty = DebugLogCounts(total: 0, errors: 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DebugLogCounts &&
          other.total == total &&
          other.errors == errors);

  @override
  int get hashCode => Object.hash(total, errors);
}

/// In-memory ring buffer of debug events (API calls, UI/platform errors, info
/// messages). All public methods are no-ops unless
/// `DebugTools.enabled`, so neither the buffer nor any captured
/// payload exists in a non-development environment.
///
/// Performance:
/// - Buffer capped at [_maxEntries].
/// - [_errorCount] maintained incrementally — chip badge never walks the list.
/// - Publish is coalesced via [scheduleMicrotask]: many synchronous log calls
///   in the same microtask cycle produce a single notifier tick, so parallel
///   API completions don't fan out into N rebuilds.
/// - Two separate notifiers: [counts] (chip) and [entries] (viewer). The chip
///   never rebuilds when only entry contents change but counts don't.
class DebugLogger {
  DebugLogger._();
  static final DebugLogger instance = DebugLogger._();

  static const int _maxEntries = 200;
  static const int _maxBodyChars = 20000;

  final Queue<DebugLogEntry> _entries = Queue<DebugLogEntry>();
  int _nextId = 0;
  int _errorCount = 0;

  final ValueNotifier<List<DebugLogEntry>> _entriesNotifier =
      ValueNotifier<List<DebugLogEntry>>(const []);
  final ValueNotifier<DebugLogCounts> _countsNotifier =
      ValueNotifier<DebugLogCounts>(DebugLogCounts.empty);

  bool _publishPending = false;

  /// Reactive view of the buffer (newest first). UI listens to this.
  ValueListenable<List<DebugLogEntry>> get entries => _entriesNotifier;

  /// Total + error counts. Cheap to subscribe to (the chip uses this).
  ValueListenable<DebugLogCounts> get counts => _countsNotifier;

  void clear() {
    if (!DebugTools.enabled) return;
    _entries.clear();
    _errorCount = 0;
    _schedulePublish();
  }

  /// Remove a single entry by id (used by the per-tile delete button).
  /// Maintains the incremental error-count invariant.
  bool remove(int id) {
    if (!DebugTools.enabled) return false;
    final list = _entries.toList();
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == id) {
        if (list[i].isError) _errorCount--;
        list.removeAt(i);
        _entries
          ..clear()
          ..addAll(list);
        _schedulePublish();
        return true;
      }
    }
    return false;
  }

  /// Records a request that just started. Returns the entry id so the
  /// interceptor can later swap it for a success/error entry via
  /// [completeApiSuccess] or [completeApiError]. Returns `null` in release.
  int? logApiInFlight({
    required String method,
    required String url,
    Map<String, String>? queryParameters,
    Map<String, String>? requestHeaders,
    String? requestBody,
  }) {
    if (!DebugTools.enabled) return null;
    final id = _nextId++;
    _add(
      DebugLogEntry(
        id: id,
        timestamp: DateTime.now(),
        kind: DebugLogKind.apiInFlight,
        title: '$method  ${_shortPath(url)}',
        subtitle: 'in-flight…',
        method: method,
        url: url,
        queryParameters: queryParameters,
        requestHeaders: requestHeaders,
        requestBody: _truncate(requestBody),
      ),
    );
    return id;
  }

  void completeApiSuccess({
    required int? id,
    required String method,
    required String url,
    required int statusCode,
    required Duration duration,
    Map<String, String>? queryParameters,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    String? requestBody,
    String? responseBody,
    int? responseBytes,
  }) {
    if (!DebugTools.enabled) return;
    final entry = DebugLogEntry(
      id: id ?? _nextId++,
      timestamp: DateTime.now(),
      kind: DebugLogKind.apiSuccess,
      title: '$method  ${_shortPath(url)}',
      subtitle:
          '$statusCode · ${duration.inMilliseconds}ms'
          '${responseBytes != null ? " · ${_formatBytes(responseBytes)}" : ""}',
      method: method,
      url: url,
      statusCode: statusCode,
      duration: duration,
      queryParameters: queryParameters,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      requestBody: _truncate(requestBody),
      responseBody: _truncate(responseBody),
      responseBytes: responseBytes,
    );
    if (id != null && _replace(id, entry)) return;
    _add(entry);
  }

  void completeApiError({
    required int? id,
    required String method,
    required String url,
    int? statusCode,
    Duration? duration,
    Map<String, String>? queryParameters,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    String? requestBody,
    String? responseBody,
    int? responseBytes,
    required String errorMessage,
  }) {
    if (!DebugTools.enabled) return;
    final entry = DebugLogEntry(
      id: id ?? _nextId++,
      timestamp: DateTime.now(),
      kind: DebugLogKind.apiError,
      title: '$method  ${_shortPath(url)}',
      subtitle:
          '${statusCode ?? "ERR"}'
          '${duration != null ? " · ${duration.inMilliseconds}ms" : ""}',
      method: method,
      url: url,
      statusCode: statusCode,
      duration: duration,
      queryParameters: queryParameters,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      requestBody: _truncate(requestBody),
      responseBody: _truncate(responseBody),
      responseBytes: responseBytes,
      errorMessage: errorMessage,
    );
    if (id != null && _replace(id, entry)) return;
    _add(entry);
  }

  void logFlutterError(FlutterErrorDetails details) {
    if (!DebugTools.enabled) return;
    final exception = details.exceptionAsString();
    _add(
      DebugLogEntry(
        id: _nextId++,
        timestamp: DateTime.now(),
        kind: DebugLogKind.flutterError,
        title: 'Flutter error',
        subtitle: _firstLine(exception),
        errorMessage: exception,
        stackTrace: details.stack?.toString(),
      ),
    );
  }

  void logPlatformError(Object error, StackTrace stackTrace) {
    if (!DebugTools.enabled) return;
    _add(
      DebugLogEntry(
        id: _nextId++,
        timestamp: DateTime.now(),
        kind: DebugLogKind.platformError,
        title: 'Uncaught error',
        subtitle: _firstLine(error.toString()),
        errorMessage: error.toString(),
        stackTrace: stackTrace.toString(),
      ),
    );
  }

  void logInfo(String title, [String? subtitle]) {
    if (!DebugTools.enabled) return;
    _add(
      DebugLogEntry(
        id: _nextId++,
        timestamp: DateTime.now(),
        kind: DebugLogKind.info,
        title: title,
        subtitle: subtitle ?? '',
      ),
    );
  }

  void _add(DebugLogEntry entry) {
    _entries.addFirst(entry);
    if (entry.isError) _errorCount++;
    while (_entries.length > _maxEntries) {
      final removed = _entries.removeLast();
      if (removed.isError) _errorCount--;
    }
    _schedulePublish();
  }

  bool _replace(int id, DebugLogEntry newEntry) {
    // Use the underlying queue's iterator with an index to avoid building a
    // full list copy when nothing actually matches.
    int index = 0;
    DebugLogEntry? target;
    for (final e in _entries) {
      if (e.id == id) {
        target = e;
        break;
      }
      index++;
    }
    if (target == null) return false;

    // Update error count delta.
    final wasError = target.isError;
    final isErrorNow = newEntry.isError;
    if (wasError && !isErrorNow) _errorCount--;
    if (!wasError && isErrorNow) _errorCount++;

    // Replace in place: convert queue to list, swap, rebuild queue.
    final list = _entries.toList(growable: false);
    list[index] = newEntry;
    _entries
      ..clear()
      ..addAll(list);

    _schedulePublish();
    return true;
  }

  /// Coalesce publishes so a burst of synchronous log calls becomes a single
  /// notifier tick. The chip and viewer redraw at most once per microtask
  /// cycle regardless of how many parallel API calls just completed.
  void _schedulePublish() {
    if (_publishPending) return;
    _publishPending = true;
    scheduleMicrotask(_publishNow);
  }

  void _publishNow() {
    _publishPending = false;
    _countsNotifier.value = DebugLogCounts(
      total: _entries.length,
      errors: _errorCount,
    );
    _entriesNotifier.value = List<DebugLogEntry>.of(_entries, growable: false);
  }

  String _shortPath(String url) {
    final qIndex = url.indexOf('?');
    final clean = qIndex == -1 ? url : url.substring(0, qIndex);
    final segments = clean.split('/');
    if (segments.length <= 2) return clean;
    return '/${segments.sublist(segments.length - 2).join('/')}';
  }

  String _firstLine(String text) {
    final i = text.indexOf('\n');
    return i == -1 ? text : text.substring(0, i);
  }

  String? _truncate(String? body) {
    if (body == null) return null;
    if (body.length <= _maxBodyChars) return body;
    return '${body.substring(0, _maxBodyChars)}\n…(truncated, ${body.length - _maxBodyChars} more chars)';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)}MB';
  }
}
