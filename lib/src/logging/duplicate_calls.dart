/// Detection of repeated identical API calls — the double-tap, the rebuild loop,
/// the effect that re-fires on every frame.
///
/// Lives here rather than inside the overlay library so it is genuinely part of
/// the public API: `AppAutopsy.diagnose` takes a `duplicates` map, and a caller
/// who cannot produce one can only pass `const {}` and silently lose the entire
/// duplicate-call branch of the network score.
library;

import 'debug_log_entry.dart';

/// The signature two requests must share to count as duplicates: the screen
/// they fired from, method, full URL (host + path), query parameters, request
/// headers and body. The requests must be *exactly* the same request — a
/// matching endpoint alone is not enough, and neither is a matching path with a
/// different host or a different header set.
///
/// The screen leads the key so the same request from two different routes never
/// groups together: that is ordinary navigation, not a double-fire. Only a
/// request that repeats *on the same screen* — a double-tap, a rebuild loop, an
/// effect re-firing every frame — is the bug this detector exists to surface.
/// When [DebugLogEntry.screen] is null (no screen observer wired) every entry
/// shares one bucket, preserving whole-session grouping.
///
/// Query parameters (from the URL and the explicit map, merged) and request
/// headers are sorted before joining, so ordering differences don't split an
/// otherwise identical pair. Headers carrying a per-request value — a rotating
/// bearer token, an `Idempotency-Key`, an `X-Request-Id` — will therefore make
/// two otherwise-identical calls *not* match, which is the intended strict
/// behaviour: those are, by definition, different requests.
String _duplicateKey(DebugLogEntry e) {
  final uri = Uri.tryParse(e.url!);
  // Full request target minus query and fragment (scheme + host + port + path),
  // so a shared path on different hosts is not treated as the same request.
  final base = _requestBase(uri, e.url!);
  final query = <String, String>{
    ...?uri?.queryParameters,
    ...?e.queryParameters,
  };
  final sortedQuery = (query.keys.toList()..sort())
      .map((k) => '$k=${query[k]}')
      .join('&');
  final headers = e.requestHeaders ?? const <String, String>{};
  final sortedHeaders = (headers.keys.toList()..sort())
      .map((k) => '$k: ${headers[k]}')
      .join('\n');
  return '${e.screen ?? ''}|${e.method}|$base|$sortedQuery|'
      '${e.requestBody ?? ''}|$sortedHeaders';
}

/// The request target with query and fragment stripped: scheme, host, port and
/// path. Relative URLs (no scheme/host) collapse to their path; an unparseable
/// URL falls back to the raw string so it still groups with its own kind.
String _requestBase(Uri? uri, String rawUrl) {
  if (uri == null) return rawUrl;
  final b = StringBuffer();
  if (uri.hasScheme) b.write('${uri.scheme}://');
  if (uri.host.isNotEmpty) b.write(uri.host);
  if (uri.hasPort) b.write(':${uri.port}');
  b.write(uri.path);
  final base = b.toString();
  return base.isEmpty ? rawUrl : base;
}

Map<String, List<DebugLogEntry>> _groupBySignature(
  List<DebugLogEntry> entries,
) {
  final byKey = <String, List<DebugLogEntry>>{};
  for (final e in entries) {
    if (!e.isApi || e.url == null || e.method == null) continue;
    byKey.putIfAbsent(_duplicateKey(e), () => []).add(e);
  }
  return byKey;
}

/// Maps entry id → how many identical calls share its signature (always ≥ 2).
/// Entries with no duplicate are omitted.
///
/// A duplicate is defined purely by the request data sent to the backend — see
/// [_duplicateKey]. Timing is not a factor: two calls with the same method,
/// URL, query, headers and body are duplicates no matter how far apart they
/// fired. Every entry in a group therefore reports the full group size ("this
/// exact request was sent 3 times"). For counting distinct *groups* rather than
/// rows, use [findDuplicateCallClusters].
///
/// Complexity: O(n) grouping.
Map<int, int> findDuplicateApiCalls(List<DebugLogEntry> entries) {
  final result = <int, int>{};
  for (final group in _groupBySignature(entries).values) {
    if (group.length < 2) continue;
    for (final e in group) {
      result[e.id] = group.length;
    }
  }
  return result;
}

/// Groups duplicates by request signature — each returned list is every call
/// that sent the identical request, oldest first, and each list has at least 2
/// entries.
///
/// Unlike [findDuplicateApiCalls] the results are disjoint: a request sent three
/// times is *one* cluster, not three overlapping rows. That distinction matters
/// when scoring, where three rows of the same mistake should count once rather
/// than triple the penalty.
///
/// A cluster is one signature, not one time-window: the same request sent every
/// minute for an hour is a single cluster of 60, because timing is not part of
/// what makes two calls duplicates. Entries are ordered by timestamp for a
/// stable, readable list only — the ordering never affects grouping.
List<List<DebugLogEntry>> findDuplicateCallClusters(
  List<DebugLogEntry> entries,
) {
  final clusters = <List<DebugLogEntry>>[];
  for (final group in _groupBySignature(entries).values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    clusters.add(group);
  }
  return clusters;
}
