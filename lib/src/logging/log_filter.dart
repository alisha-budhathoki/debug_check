/// Secondary filtering for the log list — everything beyond the primary tab.
///
/// These live in a sheet behind a single button rather than as another row of
/// chips: the header already carries the tab bar, the insight strip and the
/// search box, and a fourth permanent row would cost more vertical space than
/// the list it filters. A badge on the button carries the "you have filters on"
/// signal that a visible row would otherwise provide.
library;

import 'debug_log_entry.dart';

/// A coarse class of log entry, as a user thinks about it — not the finer
/// [DebugLogKind] the logger records.
///
/// `event` is the reason this type exists: breadcrumbs from
/// `DebugTools.breadcrumb()` were only ever visible under the All tab, because
/// the `info` filter id was taken by the App Info *panel* and the log filter
/// for it was never implemented.
enum LogCategory {
  api('API'),
  error('Errors'),
  event('Events');

  const LogCategory(this.label);
  final String label;

  bool matches(DebugLogEntry e) => switch (this) {
    LogCategory.api => e.isApi && !e.isError,
    LogCategory.error => e.isError,
    LogCategory.event => e.kind == DebugLogKind.info,
  };
}

/// HTTP status bands, which is how developers actually reason about responses
/// ("show me the 5xx") rather than by individual code.
enum StatusClass {
  success('2xx', 200, 299),
  redirect('3xx', 300, 399),
  clientError('4xx', 400, 499),
  serverError('5xx', 500, 599),
  failed('Failed', -1, -1);

  const StatusClass(this.label, this._min, this._max);
  final String label;
  final int _min;
  final int _max;

  bool matches(DebugLogEntry e) {
    final s = e.statusCode;
    // No status at all — a transport failure (DNS, timeout, offline). Worth its
    // own band: it is the one case with no code to filter on, and often the
    // most interesting.
    if (this == StatusClass.failed) return s == null && !e.isInFlight;
    return s != null && s >= _min && s <= _max;
  }
}

/// The secondary filter state. Empty sets mean "no constraint on this axis",
/// so a default instance matches everything and costs nothing to evaluate.
class LogFilter {
  final Set<LogCategory> categories;
  final Set<StatusClass> statusClasses;
  final Set<String> methods; // upper-case, e.g. {'GET', 'POST'}
  final bool pinnedOnly;

  const LogFilter({
    this.categories = const {},
    this.statusClasses = const {},
    this.methods = const {},
    this.pinnedOnly = false,
  });

  static const none = LogFilter();

  /// How many axes are constrained. Drives the badge on the filter button —
  /// axes, not values, so selecting three methods reads as one active filter
  /// rather than three.
  int get activeCount =>
      (categories.isEmpty ? 0 : 1) +
      (statusClasses.isEmpty ? 0 : 1) +
      (methods.isEmpty ? 0 : 1) +
      (pinnedOnly ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  bool matches(DebugLogEntry e) {
    if (pinnedOnly && !e.pinned) return false;
    if (categories.isNotEmpty && !categories.any((c) => c.matches(e))) {
      return false;
    }
    // Status and method only constrain API entries. A breadcrumb has neither,
    // and silently dropping it whenever a status filter is on would look like
    // the filter had eaten unrelated rows.
    if (e.isApi) {
      if (statusClasses.isNotEmpty && !statusClasses.any((s) => s.matches(e))) {
        return false;
      }
      if (methods.isNotEmpty &&
          !methods.contains((e.method ?? '').toUpperCase())) {
        return false;
      }
    } else if (statusClasses.isNotEmpty || methods.isNotEmpty) {
      // A status/method filter is inherently a question about network traffic,
      // so non-API rows drop out rather than sitting in the results unfiltered.
      return false;
    }
    return true;
  }

  LogFilter copyWith({
    Set<LogCategory>? categories,
    Set<StatusClass>? statusClasses,
    Set<String>? methods,
    bool? pinnedOnly,
  }) => LogFilter(
    categories: categories ?? this.categories,
    statusClasses: statusClasses ?? this.statusClasses,
    methods: methods ?? this.methods,
    pinnedOnly: pinnedOnly ?? this.pinnedOnly,
  );

  /// Methods actually present in [entries] — the picker offers what this
  /// session contains rather than a fixed list of every HTTP verb, most of
  /// which would return nothing.
  static List<String> methodsIn(List<DebugLogEntry> entries) {
    final set = <String>{};
    for (final e in entries) {
      final m = e.method;
      if (e.isApi && m != null && m.isNotEmpty) set.add(m.toUpperCase());
    }
    final out = set.toList()..sort();
    return out;
  }
}
