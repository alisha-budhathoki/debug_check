/// Detection of repeated identical API calls — the double-tap, the rebuild loop,
/// the effect that re-fires on every frame.
///
/// Lives here rather than inside the overlay library so it is genuinely part of
/// the public API: `AppAutopsy.diagnose` takes a `duplicates` map, and a caller
/// who cannot produce one can only pass `const {}` and silently lose the entire
/// duplicate-call branch of the network score.
library;

import 'debug_log_entry.dart';

/// The signature two requests must share to count as duplicates: method, path,
/// query parameters and body. A matching endpoint alone is not enough — the
/// same endpoint with different arguments is normal traffic, not a bug.
///
/// Query parameters from the URL and the explicit map are merged and sorted, so
/// ordering differences don't split an otherwise identical pair.
String _duplicateKey(DebugLogEntry e) {
  final uri = Uri.tryParse(e.url!);
  final path =
      uri?.path.isNotEmpty == true ? uri!.path : (uri?.toString() ?? e.url!);
  final query = <String, String>{
    ...?uri?.queryParameters,
    ...?e.queryParameters,
  };
  final sortedQuery = (query.keys.toList()..sort())
      .map((k) => '$k=${query[k]}')
      .join('&');
  return '${e.method}|$path|$sortedQuery|${e.requestBody ?? ''}';
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

/// Maps entry id → how many identical calls surround it within [window]
/// (always ≥ 2). Entries with no duplicate are omitted.
///
/// Each entry is measured from its own position, so overlapping runs are each
/// reported at full size — the right behaviour for badging an individual row
/// ("this call fired 3 times"). For counting distinct *bursts*, use
/// [findDuplicateCallClusters] instead.
///
/// Complexity: O(n) grouping plus a linear sweep per group.
Map<int, int> findDuplicateApiCalls(
  List<DebugLogEntry> entries, {
  Duration window = const Duration(seconds: 5),
}) {
  final result = <int, int>{};
  for (final group in _groupBySignature(entries).values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (var i = 0; i < group.length; i++) {
      var clusterSize = 1;
      for (var j = i - 1; j >= 0; j--) {
        if (group[i].timestamp.difference(group[j].timestamp) > window) break;
        clusterSize++;
      }
      for (var j = i + 1; j < group.length; j++) {
        if (group[j].timestamp.difference(group[i].timestamp) > window) break;
        clusterSize++;
      }
      if (clusterSize > 1) result[group[i].id] = clusterSize;
    }
  }
  return result;
}

/// Groups duplicates into distinct bursts — each returned list is one run of
/// identical calls, oldest first, and every list has at least 2 entries.
///
/// Unlike [findDuplicateApiCalls] the results are disjoint: a request that
/// fires three times in a row is *one* cluster, not three overlapping ones.
/// That distinction matters when scoring, where three rows of the same mistake
/// should count once rather than triple the penalty.
///
/// A run is broken when the gap between consecutive calls exceeds [window], so
/// the same request firing every minute for an hour is many small clusters, not
/// one large one.
List<List<DebugLogEntry>> findDuplicateCallClusters(
  List<DebugLogEntry> entries, {
  Duration window = const Duration(seconds: 5),
}) {
  final clusters = <List<DebugLogEntry>>[];
  for (final group in _groupBySignature(entries).values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    var run = <DebugLogEntry>[group.first];
    for (var i = 1; i < group.length; i++) {
      final gap = group[i].timestamp.difference(group[i - 1].timestamp);
      if (gap <= window) {
        run.add(group[i]);
      } else {
        if (run.length >= 2) clusters.add(run);
        run = <DebugLogEntry>[group[i]];
      }
    }
    if (run.length >= 2) clusters.add(run);
  }
  return clusters;
}
