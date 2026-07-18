/// Whole-session export.
///
/// The per-call exports (cURL / JSON / HAR) answer "what did *this* request
/// do". A bug report needs the other question — "what was the app doing" —
/// which means the diagnosis, the breadcrumb trail, the failures and the
/// device facts in one artefact, in the order they happened.
///
/// Everything here is a pure function of data already captured, so it does no
/// I/O and is callable from a test or a CI script, not just the overlay.
library;

import 'dart:convert';

import '../app_info/app_info_snapshot.dart';
import '../autopsy/app_autopsy.dart';
import '../core/debug_tools.dart';
import '../logging/debug_log_entry.dart';
import '../logging/duplicate_calls.dart';
import '../performance/perf_monitor.dart';

/// Builds shareable artefacts describing a whole debugging session.
class SessionExport {
  const SessionExport._();

  /// A Markdown bug report: verdict, environment, what failed, and the trail
  /// that led there.
  ///
  /// Ordered for the reader, not the writer — the grade and the failures come
  /// first, because whoever opens the issue decides in seconds whether it is
  /// theirs. Raw traffic goes last.
  ///
  /// [maxTimeline] bounds the trail so a 200-entry session doesn't produce an
  /// issue body nobody scrolls; when entries are dropped it says so rather than
  /// silently truncating.
  static String toMarkdown({
    required List<DebugLogEntry> entries,
    required PerfStats perf,
    AppInfoSnapshot? appInfo,
    int maxTimeline = 40,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final autopsy = AppAutopsy.diagnose(entries: entries, perf: perf, now: at);
    final api = entries.where((e) => e.isApi).toList(growable: false);
    final errors = entries.where((e) => e.isError).toList(growable: false);
    final clusters = findDuplicateCallClusters(entries);
    final b = StringBuffer();

    b.writeln('# Session report');
    b.writeln();
    b.writeln(
      '**${autopsy.grade.letter} · ${autopsy.grade.label}** — '
      '${autopsy.headline}',
    );
    b.writeln();

    b.writeln('| | |');
    b.writeln('|---|---|');
    b.writeln('| Generated | ${_stamp(at)} |');
    b.writeln(
      '| App | ${DebugTools.appInfo.version} '
      '(${DebugTools.appInfo.environmentName}) |',
    );
    b.writeln('| Base URL | `${DebugTools.appInfo.baseUrl}` |');
    if (appInfo != null) {
      b.writeln('| Platform | ${appInfo.os} ${appInfo.osVersion} |');
      b.writeln(
        '| Screen | ${appInfo.screenSize.width.toStringAsFixed(0)}'
        '×${appInfo.screenSize.height.toStringAsFixed(0)} '
        '@${appInfo.devicePixelRatio}x |',
      );
      b.writeln('| Uptime | ${appInfo.uptimeReadable} |');
    }
    b.writeln(
      '| Requests | ${api.length} '
      '(${autopsy.apiErrors} failed) |',
    );
    b.writeln('| Errors | ${errors.length} |');
    if (perf.hasData) {
      b.writeln(
        '| Rendering | ${perf.fps} fps, '
        '${(perf.jankRatio * 100).toStringAsFixed(1)}% janky |',
      );
    }
    b.writeln();

    // The diagnosis, already prioritized worst-first.
    b.writeln('## Diagnosis');
    b.writeln();
    for (final f in autopsy.findings) {
      b.writeln('- **${_severity(f.severity)} ${f.title}** — ${f.detail}');
    }
    b.writeln();

    if (errors.isNotEmpty) {
      b.writeln('## Failures');
      b.writeln();
      for (final e in errors) {
        final code = e.statusCode == null ? '' : ' `${e.statusCode}`';
        b.writeln('- `${_time(e.timestamp)}`$code ${e.title}');
        final msg = e.errorMessage;
        if (msg != null && msg.isNotEmpty) {
          b.writeln('  - ${_firstLine(msg)}');
        }
      }
      b.writeln();
    }

    if (clusters.isNotEmpty) {
      b.writeln('## Repeated calls');
      b.writeln();
      for (final c in clusters) {
        b.writeln(
          '- ${c.length}× `${c.first.method} ${_path(c.first.url)}` '
          'within ${_span(c)}',
        );
      }
      b.writeln();
    }

    b.writeln('## Timeline');
    b.writeln();
    final shown =
        entries.length > maxTimeline
            ? entries.sublist(0, maxTimeline)
            : entries;
    for (final e in shown) {
      b.writeln('- `${_time(e.timestamp)}` ${_line(e)}');
    }
    if (entries.length > shown.length) {
      // Say what was dropped. A silently truncated list reads as a complete one.
      b.writeln();
      b.writeln('_…${entries.length - shown.length} earlier entries omitted._');
    }

    return b.toString();
  }

  /// A HAR 1.2 archive of every captured request, for a HAR viewer or browser
  /// devtools. Non-API entries have no HAR representation and are skipped.
  ///
  /// Header values follow the current reveal preference, so a masked session
  /// exports masked.
  static String toHar({required List<DebugLogEntry> entries, DateTime? now}) {
    List<Map<String, String>> nv(Map<String, String>? m) =>
        (DebugTools.visible(m)?.entries ?? const <MapEntry<String, String>>[])
            .map((e) => {'name': e.key, 'value': e.value})
            .toList();

    final api = entries.where((e) => e.isApi).toList(growable: false);
    final har = <String, dynamic>{
      'log': {
        'version': '1.2',
        'creator': {'name': 'debug_deck', 'version': '1.0'},
        'comment':
            'App ${DebugTools.appInfo.version} '
            '(${DebugTools.appInfo.environmentName})',
        'entries': [
          for (final e in api)
            {
              'startedDateTime': e.timestamp.toUtc().toIso8601String(),
              'time': e.duration?.inMilliseconds ?? 0,
              'request': {
                'method': e.method ?? 'GET',
                'url': e.url ?? '',
                'httpVersion': 'HTTP/1.1',
                'headers': nv(e.requestHeaders),
                'queryString': nv(e.queryParameters),
                'cookies': const [],
                'headersSize': -1,
                'bodySize': e.requestBody?.length ?? 0,
                if (e.requestBody?.isNotEmpty ?? false)
                  'postData': {
                    'mimeType': 'application/json',
                    'text': e.requestBody,
                  },
              },
              'response': {
                'status': e.statusCode ?? 0,
                'statusText': '',
                'httpVersion': 'HTTP/1.1',
                'headers': nv(e.responseHeaders),
                'cookies': const [],
                'content': {
                  'size': e.responseBytes ?? 0,
                  'mimeType': 'application/json',
                  if (e.responseBody != null) 'text': e.responseBody,
                },
                'redirectURL': '',
                'headersSize': -1,
                'bodySize': e.responseBytes ?? 0,
              },
              'cache': const {},
              'timings': {
                'send': 0,
                'wait': e.duration?.inMilliseconds ?? 0,
                'receive': 0,
              },
            },
        ],
      },
    };
    return const JsonEncoder.withIndent('  ').convert(har);
  }

  // ── helpers ──

  static String _severity(AutopsySeverity s) => switch (s) {
    AutopsySeverity.critical => '🔴',
    AutopsySeverity.warning => '🟡',
    AutopsySeverity.info => '🔵',
    AutopsySeverity.good => '🟢',
  };

  static String _line(DebugLogEntry e) {
    if (e.isApi) {
      final code = e.statusCode?.toString() ?? 'ERR';
      final ms = e.duration?.inMilliseconds;
      return '`$code` ${e.method} ${_path(e.url)}'
          '${ms == null ? '' : ' · ${ms}ms'}';
    }
    if (e.isError) return '**${e.title}** — ${_firstLine(e.subtitle)}';
    return '${e.title}${e.subtitle.isEmpty ? '' : ' — ${e.subtitle}'}';
  }

  static String _path(String? url) {
    if (url == null) return '-';
    final u = Uri.tryParse(url);
    if (u == null) return url;
    return u.path.isEmpty ? url : u.path;
  }

  static String _span(List<DebugLogEntry> cluster) {
    final ms =
        cluster.last.timestamp
            .difference(cluster.first.timestamp)
            .inMilliseconds;
    return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
  }

  static String _firstLine(String s) {
    final i = s.indexOf('\n');
    return i == -1 ? s : s.substring(0, i);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _time(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static String _stamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_time(t)}';
}
