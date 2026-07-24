part of 'debug_overlay.dart';

class _DebugLogViewer extends StatefulWidget {
  final List<DebugLogEntry> entries;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback onHide;

  const _DebugLogViewer({
    required this.entries,
    required this.onMinimize,
    required this.onClose,
    required this.onHide,
  });

  @override
  State<_DebugLogViewer> createState() => _DebugLogViewerState();
}

class _DebugLogViewerState extends State<_DebugLogViewer> {
  // Tab ids. 'app' (not 'info') names the App Info panel: DebugLogKind.info is
  // what breadcrumbs are recorded as, and having the panel own that id meant
  // the log filter for breadcrumbs could never be written.
  String _filter = 'all'; // all | api | errors | autopsy | app | perf | grid
  String _search = '';
  LogFilter _advanced = LogFilter.none;
  int? _detailId; // open API detail screen (by entry id, for live freshness)
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(DebugLogEntry e) {
    switch (_filter) {
      case 'api':
        if (!e.isApi) return false;
        break;
      case 'errors':
        if (!e.isError) return false;
        break;
    }
    if (!_advanced.matches(e)) return false;
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return e.title.toLowerCase().contains(q) ||
        (e.url?.toLowerCase().contains(q) ?? false) ||
        (e.errorMessage?.toLowerCase().contains(q) ?? false) ||
        e.subtitle.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    // A selected API entry takes over the viewer with the tabbed detail screen.
    if (_detailId != null) {
      DebugLogEntry? entry;
      for (final e in widget.entries) {
        if (e.id == _detailId) {
          entry = e;
          break;
        }
      }
      if (entry != null) {
        return _ApiDetailScreen(
          entry: entry,
          onBack: () => setState(() => _detailId = null),
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
        );
      }
    }

    final isInfoTab = _filter == 'app';
    final isGridTab = _filter == 'grid';
    final isPerfTab = _filter == 'perf';
    final isAutopsyTab = _filter == 'autopsy';
    // Autopsy, Info, Grid and Perf are control panels, not log lists.
    final isPanelTab = isInfoTab || isGridTab || isPerfTab || isAutopsyTab;
    final filtered =
        isPanelTab
            ? const <DebugLogEntry>[]
            : widget.entries.where(_matches).toList(growable: false);
    final dupes =
        isPanelTab ? const <int, int>{} : findDuplicateApiCalls(widget.entries);
    final dupeRows = filtered.where((e) => dupes.containsKey(e.id)).length;

    return Material(
      color: const Color(0xFF0E1116),
      child: SafeArea(
        child: Column(
          children: [
            _ViewerHeader(
              filter: _filter,
              onFilterChange: (f) => setState(() => _filter = f),
              onClear: () => DebugLogger.instance.clear(),
              onMinimize: widget.onMinimize,
              onClose: widget.onClose,
              onHide: widget.onHide,
              total: widget.entries.length,
              shown: filtered.length,
              entries: widget.entries,
              duplicateRows: dupeRows,
              searchCtrl: _searchCtrl,
              onSearchChanged: (v) => setState(() => _search = v),
              searchEnabled: !isPanelTab,
              advanced: _advanced,
              onAdvancedChange: (f) => setState(() => _advanced = f),
            ),
            if (!isPanelTab && dupeRows > 0)
              _DuplicateWarningBar(count: dupeRows),
            Expanded(
              child:
                  isAutopsyTab
                      ? const _AutopsyPanel()
                      : isGridTab
                      ? const DebugGridPanel()
                      : isPerfTab
                      ? const _PerfPanel()
                      : isInfoTab
                      ? const _AppInfoPanel()
                      : filtered.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final entry = filtered[i];
                          return _LogTile(
                            entry: entry,
                            duplicateCount: dupes[entry.id],
                            onOpen: (e) => setState(() => _detailId = e.id),
                            onTogglePin:
                                (e) => setState(
                                  () => DebugLogger.instance.togglePin(e.id),
                                ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text(
            'No matching logs',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Performance panel (FPS / jank / frame timings) ──────────────────────────

/// Live rendering-performance read-out for QA: frames/sec, jank %, worst frame
/// and a frame-time sparkline. Reads [PerfMonitor], which records every frame
/// from boot, so minimise the tools, exercise a screen, then reopen this tab.

/// The endpoint path, rendered with the leading segments dimmed and the final
/// segment — the resource the call actually hits — kept bright, so the eye
/// lands on what matters while the full path stays legible. Wraps freely and
/// never truncates.
class _EndpointPath extends StatelessWidget {
  final String path;
  const _EndpointPath({required this.path});

  @override
  Widget build(BuildContext context) {
    final trimmed =
        path.length > 1 && path.endsWith('/')
            ? path.substring(0, path.length - 1)
            : path;
    final slash = trimmed.lastIndexOf('/');
    var lead = slash <= 0 ? '' : trimmed.substring(0, slash + 1);
    var leaf = slash < 0 ? trimmed : trimmed.substring(slash + 1);
    if (leaf.isEmpty) {
      leaf = trimmed;
      lead = '';
    }

    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          height: 1.35,
        ),
        children: [
          if (lead.isNotEmpty)
            TextSpan(text: lead, style: const TextStyle(color: Colors.white54)),
          TextSpan(text: leaf, style: const TextStyle(color: Colors.white)),
        ],
      ),
      softWrap: true,
    );
  }
}

/// Query parameters as a wrapping row of decoded key/value pills — far more
/// scannable than a long `?a=b&c=d` string trailing the path, and it keeps the
/// path itself clean.
class _QueryParams extends StatelessWidget {
  final Map<String, String> params;
  const _QueryParams({required this.params});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in params.entries) _QueryChip(name: e.key, value: e.value),
      ],
    );
  }
}

class _QueryChip extends StatelessWidget {
  final String name;
  final String value;
  const _QueryChip({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF61AFEF);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2530),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 10.5,
            fontFamily: 'monospace',
            height: 1.1,
          ),
          children: [
            TextSpan(text: name, style: const TextStyle(color: Colors.white54)),
            const TextSpan(
              text: ' = ',
              style: TextStyle(color: Colors.white24),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _DuplicateBadge extends StatelessWidget {
  final int count;
  const _DuplicateBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE5C07B).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFE5C07B).withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.copy_all_outlined,
            color: Color(0xFFE5C07B),
            size: 10,
          ),
          const SizedBox(width: 3),
          Text(
            '×$count',
            style: const TextStyle(
              color: Color(0xFFE5C07B),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact red-tinted strip shown under a failed API row so the failure reason
/// is visible in the list itself, no detail screen required.
class _ApiErrorLine extends StatelessWidget {
  final String text;
  const _ApiErrorLine({required this.text});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE06C75);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: red, size: 13),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFF2B8BD),
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateWarningBar extends StatelessWidget {
  final int count;
  const _DuplicateWarningBar({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF332515),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFE5C07B),
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$count duplicate API call${count == 1 ? "" : "s"} detected '
              '(identical request repeated on the same screen)',
              style: const TextStyle(
                color: Color(0xFFE5C07B),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── App info panel ──────────────────────────────────────────────────────────

class _ViewerHeader extends StatelessWidget {
  final String filter;
  final ValueChanged<String> onFilterChange;
  final VoidCallback onClear;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback onHide;
  final int total;
  final int shown;
  final List<DebugLogEntry> entries;
  final int duplicateRows;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;

  /// The search box only filters the log list, so on the panel tabs (Info /
  /// Perf / Grid) it is shown but disabled — present to keep the header a fixed
  /// height, inert so it plainly has no effect there.
  final bool searchEnabled;

  /// Secondary filters (category / status class / method / pinned) and their
  /// setter. Kept behind a button rather than another header row — see
  /// [LogFilter]'s docs for why.
  final LogFilter advanced;
  final ValueChanged<LogFilter> onAdvancedChange;

  const _ViewerHeader({
    required this.filter,
    required this.onFilterChange,
    required this.onClear,
    required this.onMinimize,
    required this.onClose,
    required this.onHide,
    required this.total,
    required this.shown,
    required this.entries,
    required this.duplicateRows,
    required this.searchCtrl,
    required this.advanced,
    required this.onAdvancedChange,
    required this.onSearchChanged,
    this.searchEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bug_report_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Debug · $shown of $total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Whole-session export — the artefact you actually attach to a
              // bug report, as opposed to the per-call exports inside a detail.
              _HeaderIconButton(
                icon: Icons.ios_share,
                tooltip: 'Export session',
                onTap: () => _showSessionExport(context, entries),
              ),
              const SizedBox(width: 2),
              _HeaderIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Clear logs',
                onTap: onClear,
              ),
              const SizedBox(width: 2),
              // Minimize: keeps the viewer's place (filter, search, open detail,
              // scroll) so you can pop back to the app and return where you were.
              // Same effect as tapping the floating chip.
              _HeaderIconButton(
                icon: Icons.remove,
                tooltip: 'Minimize — keeps your place',
                onTap: onMinimize,
              ),
              const SizedBox(width: 2),
              // Close: tears the viewer down so a reopen starts from the log list.
              _HeaderIconButton(
                icon: Icons.close,
                tooltip: 'Close — reset to start',
                onTap: onClose,
              ),
              const SizedBox(width: 2),
              _HeaderIconButton(
                icon: Icons.visibility_off_outlined,
                tint: const Color(0xFFE06C75),
                tooltip: 'Hide debug overlay',
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onHide();
                },
              ),
            ],
          ),
          // Primary navigation. Sits directly under the title so it reads as
          // the main control of the panel; everything below it is context for
          // whichever tab it selects. A segmented control (not loose chips)
          // gives the tabs the visual weight of a real switcher.
          const SizedBox(height: 12),
          _TabBar(
            filter: filter,
            // Counted off the unfiltered entry list, so the badge always
            // reflects every error captured — not just what search matches.
            errorCount: entries.where((e) => e.isError).length,
            onFilterChange: onFilterChange,
          ),
          // Context layer for the active tab — visually lighter than the tabs
          // above it. A fixed-height insight strip (so switching tabs never
          // resizes the header) with at-a-glance metrics, then the search box.
          const SizedBox(height: 12),
          _InsightStrip(
            filter: filter,
            entries: entries,
            duplicateRows: duplicateRows,
          ),
          // Search stays mounted on every tab (fixed height) but is disabled on
          // the panel tabs, where it has nothing to filter — inert, not hidden.
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SearchField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  enabled: searchEnabled,
                ),
              ),
              const SizedBox(width: 6),
              _FilterButton(
                active: advanced,
                enabled: searchEnabled, // same tabs the search box applies to
                entries: entries,
                onChange: onAdvancedChange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the secondary-filter sheet, badged with how many axes are constrained
/// so an active filter is never invisible — otherwise a filtered-empty list
/// reads as "no logs" and sends people hunting for a bug that isn't there.
class _FilterButton extends StatelessWidget {
  final LogFilter active;
  final bool enabled;
  final List<DebugLogEntry> entries;
  final ValueChanged<LogFilter> onChange;

  const _FilterButton({
    required this.active,
    required this.enabled,
    required this.entries,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final count = active.activeCount;
    final on = count > 0;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            !enabled
                ? null
                : () async {
                  HapticFeedback.selectionClick();
                  final result = await showModalBottomSheet<LogFilter>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder:
                        (_) => _FilterSheet(initial: active, entries: entries),
                  );
                  if (result != null) onChange(result);
                },
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF1B2B3A) : const Color(0xFF0B0E13),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color:
                  on
                      ? const Color(0xFF61AFEF).withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 16,
                color: on ? const Color(0xFF61AFEF) : Colors.white54,
              ),
              if (on) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Color(0xFF61AFEF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  const _SearchField({
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // Disabled on panel tabs: dimmed and non-interactive so it reads as "not
    // applicable here" rather than a search box that silently does nothing.
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E1116),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          enabled: enabled,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          cursorColor: Colors.white70,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: InputBorder.none,
            disabledBorder: InputBorder.none,
            hintText:
                enabled
                    ? 'Search URL, error, title…'
                    : 'Search applies to logs',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon: const Icon(
              Icons.search,
              color: Colors.white38,
              size: 18,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;
  final String? tooltip;
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tint,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: tint ?? Colors.white70, size: 20),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// A compact, unobtrusive copy affordance for inline use in a log row — e.g.
/// lifting the full request URL straight from the list without opening detail.
class _InlineCopyButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  const _InlineCopyButton({required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: Icon(Icons.copy_rounded, size: 13, color: Colors.white38),
        ),
      ),
    );
  }
}

/// A single glanceable metric: a coloured icon + value with a dim trailing
/// label, e.g. `⏱ 512ms avg`. The value carries the colour (so a bad number
/// reads as red at a glance); the label stays quiet so the strip scans fast.
class _InsightPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _InsightPill({
    required this.icon,
    required this.value,
    required this.label,
    this.color = const Color(0xFF61AFEF),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A fixed-height, horizontally-scrolling band of [_InsightPill]s that gives
/// each tab an at-a-glance summary of what it contains. Present (and the same
/// height) on every tab, it is what keeps the header a fixed height while still
/// turning that space into something useful:
///
///  • log tabs → traffic totals (requests, errors, avg latency, data, dupes)
///  • Info     → app identity (version, environment, host, channel)
///  • Perf     → live FPS / jank / worst-frame, refreshed as frames land
///  • Grid     → device geometry (logical size, DPR, text scale)
class _InsightStrip extends StatelessWidget {
  final String filter;
  final List<DebugLogEntry> entries;
  final int duplicateRows;
  const _InsightStrip({
    required this.filter,
    required this.entries,
    required this.duplicateRows,
  });

  static const _blue = Color(0xFF61AFEF);
  static const _green = Color(0xFF98C379);
  static const _amber = Color(0xFFE5C07B);
  static const _red = Color(0xFFE06C75);
  static const _cyan = Color(0xFF56B6C2);
  static const _violet = Color(0xFFC678DD);
  static const _idle = Colors.white38;

  @override
  Widget build(BuildContext context) {
    // Perf and Autopsy change continuously, so they rebuild off the live stats
    // notifier; every other tab is derived from data in hand.
    if (filter == 'perf') {
      return ValueListenableBuilder<PerfStats>(
        valueListenable: PerfMonitor.instance.stats,
        builder: (_, stats, _) => _band(_perfPills(stats)),
      );
    }
    if (filter == 'autopsy') {
      return ValueListenableBuilder<PerfStats>(
        valueListenable: PerfMonitor.instance.stats,
        builder: (_, stats, _) => _band(_autopsyPills(stats)),
      );
    }
    switch (filter) {
      case 'app':
        return _band(_infoPills());
      case 'grid':
        return _band(_gridPills(context));
      default:
        return _band(_logPills());
    }
  }

  Widget _band(List<Widget> pills) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(child: pills[i]),
      ),
    );
  }

  // ─── Per-tab pills ─────────────────────────────────────────────────────────

  List<Widget> _logPills() {
    final api = entries.where((e) => e.isApi).toList(growable: false);
    final errors = entries.where((e) => e.isError).length;
    final latencies = api
        .where((e) => e.duration != null)
        .map((e) => e.duration!.inMilliseconds)
        .toList(growable: false);
    final avg =
        latencies.isEmpty
            ? null
            : latencies.reduce((a, b) => a + b) ~/ latencies.length;
    final bytes = api.fold<int>(0, (s, e) => s + (e.responseBytes ?? 0));

    return [
      _InsightPill(
        icon: Icons.swap_vert_rounded,
        value: '${api.length}',
        label: api.length == 1 ? 'request' : 'requests',
        color: _blue,
      ),
      _InsightPill(
        icon: errors > 0 ? Icons.error_outline : Icons.check_circle_outline,
        value: '$errors',
        label: errors == 1 ? 'error' : 'errors',
        color: errors > 0 ? _red : _green,
      ),
      if (avg != null)
        _InsightPill(
          icon: Icons.timer_outlined,
          value: '${avg}ms',
          label: 'avg',
          color: _latencyColor(avg),
        ),
      if (bytes > 0)
        _InsightPill(
          icon: Icons.download_outlined,
          value: _formatBytes(bytes),
          label: 'transferred',
          color: _cyan,
        ),
      if (duplicateRows > 0)
        _InsightPill(
          icon: Icons.copy_all_outlined,
          value: '$duplicateRows',
          label: duplicateRows == 1 ? 'duplicate' : 'duplicates',
          color: _amber,
        ),
    ];
  }

  List<Widget> _infoPills() {
    final info = DebugTools.appInfo;
    String? clean(String v) => (v.isEmpty || v == '-') ? null : v;
    final version = clean(info.version);
    final env = clean(info.environmentName);
    final host = clean(Uri.tryParse(info.baseUrl)?.host ?? '');

    return [
      if (version != null)
        _InsightPill(
          icon: Icons.tag,
          value: version,
          label: 'version',
          color: _blue,
        ),
      if (env != null)
        _InsightPill(
          icon: Icons.dns_outlined,
          value: env,
          label: 'env',
          color: _violet,
        ),
      if (host != null)
        _InsightPill(
          icon: Icons.public,
          value: host,
          label: 'host',
          color: _cyan,
        ),
      _InsightPill(
        icon: info.isNativeCall ? Icons.phonelink : Icons.language,
        value: info.isNativeCall ? 'native' : 'http',
        label: 'channel',
        color: _green,
      ),
    ];
  }

  List<Widget> _gridPills(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    return [
      _InsightPill(
        icon: Icons.aspect_ratio,
        value: '${size.width.round()}×${size.height.round()}',
        label: 'logical',
        color: _blue,
      ),
      _InsightPill(
        icon: Icons.grain,
        value: '${mq.devicePixelRatio.toStringAsFixed(1)}×',
        label: 'dpr',
        color: _cyan,
      ),
      _InsightPill(
        icon: Icons.format_size,
        value: '${mq.textScaler.scale(1).toStringAsFixed(2)}×',
        label: 'text scale',
        color: _violet,
      ),
    ];
  }

  List<Widget> _perfPills(PerfStats stats) {
    final rendering = stats.sampleCount > 0 && stats.fps > 0;
    final jankPct = stats.jankRatio * 100;
    return [
      _InsightPill(
        icon: Icons.speed,
        value: rendering ? stats.fps.toStringAsFixed(0) : 'idle',
        label: 'fps',
        color:
            !rendering
                ? _idle
                : stats.fps >= 55
                ? _green
                : stats.fps >= 40
                ? _amber
                : _red,
      ),
      _InsightPill(
        icon: Icons.stacked_line_chart,
        value: '${jankPct.toStringAsFixed(0)}%',
        label: 'jank',
        color:
            stats.jankRatio <= 0.05
                ? _green
                : stats.jankRatio <= 0.15
                ? _amber
                : _red,
      ),
      _InsightPill(
        icon: Icons.warning_amber_rounded,
        value: '${stats.worstTotalMs.toStringAsFixed(0)}ms',
        label: 'worst',
        color:
            stats.worstTotalMs <= 16.7
                ? _green
                : stats.worstTotalMs <= 33
                ? _amber
                : _red,
      ),
    ];
  }

  List<Widget> _autopsyPills(PerfStats stats) {
    final a = AppAutopsy.diagnose(entries: entries, perf: stats);
    Color gradeColor(AutopsyGrade g) {
      switch (g) {
        case AutopsyGrade.a:
        case AutopsyGrade.b:
          return _green;
        case AutopsyGrade.c:
          return _amber;
        case AutopsyGrade.d:
        case AutopsyGrade.f:
          return _red;
      }
    }

    return [
      _InsightPill(
        icon: Icons.monitor_heart_outlined,
        value: '${a.grade.letter} · ${a.score}',
        label: 'health',
        color: gradeColor(a.grade),
      ),
      if (a.criticalCount > 0)
        _InsightPill(
          icon: Icons.error_outline,
          value: '${a.criticalCount}',
          label: 'critical',
          color: _red,
        ),
      if (a.warningCount > 0)
        _InsightPill(
          icon: Icons.warning_amber_rounded,
          value: '${a.warningCount}',
          label: a.warningCount == 1 ? 'warning' : 'warnings',
          color: _amber,
        ),
      if (a.criticalCount == 0 && a.warningCount == 0)
        const _InsightPill(
          icon: Icons.check_circle_outline,
          value: 'clean',
          label: 'no issues',
          color: _green,
        ),
    ];
  }

  // ─── Local formatting (mirrors the row helpers; kept self-contained) ────────

  static Color _latencyColor(int ms) {
    if (ms <= 300) return _green;
    if (ms <= 1000) return _amber;
    return _red;
  }

  static String _formatBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)}MB';
  }
}

/// The primary tab switcher, styled as an iOS-style segmented control: an
/// inset track holding equal-width segments, with a raised thumb marking the
/// selected tab. This reads as one deliberate navigation control — giving the
/// tabs clear visual weight — rather than a scattered row of chips that gets
/// lost under the rest of the header.
class _TabBar extends StatelessWidget {
  final String filter;
  final int errorCount;
  final ValueChanged<String> onFilterChange;
  const _TabBar({
    required this.filter,
    required this.errorCount,
    required this.onFilterChange,
  });

  // (id, label). Log filters first, then the tool panels.
  static const _tabs = <(String, String)>[
    ('all', 'All'),
    ('api', 'API'),
    ('errors', 'Errors'),
    ('autopsy', 'Autopsy'),
    ('app', 'App'),
    ('perf', 'Perf'),
    ('grid', 'Grid'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in _tabs)
            Expanded(
              // The Errors tab claims ~1.5× width once errors exist, so the
              // count badge sits beside the label instead of squeezing it.
              // Flips once (0 → non-zero), not per new error.
              flex: t.$1 == 'errors' && errorCount > 0 ? 3 : 2,
              child: _TabSegment(
                label: t.$2,
                selected: filter == t.$1,
                badgeCount: t.$1 == 'errors' ? errorCount : 0,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFilterChange(t.$1);
                },
              ),
            ),
        ],
      ),
    );
  }
}

// Alert palette for the Errors tab.
const Color _alertRed = Color(0xFFE5484D); // badge fill / glow source
const Color _alertText = Color(0xFFFF938C); // label on the unselected wash
const Color _alertWash = Color(0xFF2B1518); // flat unselected background
const Color _alertPeak = Color(0xFF7A2830); // unselected fill at pulse peak
const Color _alertThumb = Color(0xFF5E2126); // raised background when selected

class _TabSegment extends StatefulWidget {
  final String label;
  final bool selected;

  /// When > 0 the segment takes the alert treatment and carries a count badge.
  /// Used by the Errors tab so a failing app is obvious the moment the deck
  /// opens, without the user having to visit the tab to find out.
  final int badgeCount;
  final VoidCallback onTap;
  const _TabSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  State<_TabSegment> createState() => _TabSegmentState();
}

class _TabSegmentState extends State<_TabSegment>
    with SingleTickerProviderStateMixin {
  // Colour alone can't compete with the raised thumb for attention, and making
  // it loud enough to try would just read as a second selected tab. Motion is
  // what actually catches the eye on first open, so the segment breathes a red
  // glow for a few cycles and then settles into a calm, permanently-tinted
  // state. It re-arms whenever the count climbs, so an app that keeps throwing
  // errors keeps glowing, then quiets down once the errors stop.
  static const _pulseCycles = 4;
  late final AnimationController _pulse;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _lastCount = widget.badgeCount;
    // Errors already present when the deck first builds — the exact case the
    // pulse exists for.
    if (widget.badgeCount > 0 && !widget.selected) _armPulse();
  }

  // Bumped on every arm so a superseded run's completion callback can't reset
  // the glow out from under the run that replaced it.
  int _pulseGeneration = 0;

  void _armPulse() {
    final generation = ++_pulseGeneration;
    _pulse.reset();
    // repeat() leaves the controller wherever the last traversal ended, which
    // isn't reliably 0 — without this the tab keeps a faint permanent halo.
    _pulse.repeat(reverse: true, count: _pulseCycles * 2).whenCompleteOrCancel(
      () {
        if (mounted && generation == _pulseGeneration) _pulse.value = 0;
      },
    );
  }

  @override
  void didUpdateWidget(_TabSegment old) {
    super.didUpdateWidget(old);
    // Visiting the tab is acknowledgement: stop nagging.
    if (widget.selected) {
      if (_pulse.isAnimating) _pulse.stop();
    } else if (widget.badgeCount > _lastCount) {
      _armPulse();
    }
    _lastCount = widget.badgeCount;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerting = widget.badgeCount > 0;
    final selected = widget.selected;

    final Color fill;
    if (alerting) {
      fill = selected ? _alertThumb : _alertWash;
    } else {
      fill = selected ? const Color(0xFF2D333B) : Colors.transparent;
    }
    final labelColor =
        alerting
            ? (selected ? Colors.white : _alertText)
            : (selected ? Colors.white : Colors.white54);

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              color: labelColor,
              fontSize: 11.5,
              fontWeight:
                  selected || alerting ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (alerting) ...[
          const SizedBox(width: 5),
          _ErrorBadge(count: widget.badgeCount, onThumb: selected),
        ],
      ],
    );

    Widget segment(Color background) => AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      padding: alerting ? const EdgeInsets.symmetric(horizontal: 5) : null,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        // Only the *selected* segment gets a shadow. An unselected alerting tab
        // stays deliberately flat — even at the pulse peak — so the control
        // never looks like it has two active segments. The tint, badge and
        // motion carry the urgency; the raised thumb keeps meaning "current
        // tab".
        boxShadow:
            selected
                ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
                : null,
      ),
      child: content,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child:
          alerting && !selected
              ? AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_pulse.value);
                  return DecoratedBox(
                    key: const Key('debugDeck.errorTabGlow'),
                    // The halo sits on an outer box so it renders behind the
                    // segment fill and bleeds out over the track — that spill
                    // past the segment's own edges is what catches the eye from
                    // the corner of the screen.
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _alertRed.withValues(alpha: 0.85 * t),
                          blurRadius: 18,
                          spreadRadius: 3 * t,
                        ),
                      ],
                    ),
                    // The fill brightens in step with the halo. Halo alone was
                    // too close in value to the resting wash to read as motion.
                    child: segment(Color.lerp(_alertWash, _alertPeak, t)!),
                  );
                },
              )
              : segment(fill),
    );
  }
}

/// Count pill for the Errors tab — sized to sit *inside* the segment as a
/// compact numeral rather than a blob that rivals the label. Caps at 99+ so a
/// flood of errors can never widen the segment past its share of the track.
class _ErrorBadge extends StatelessWidget {
  final int count;

  /// On the selected (raised red) segment the solid fill loses contrast, so the
  /// badge inverts to a light chip instead.
  final bool onThumb;
  const _ErrorBadge({required this.count, required this.onThumb});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      // Fixed height rather than vertical padding: letting the font's line
      // metrics set the height made the pill taller than it was wide, so it
      // rendered as a capsule stood on end instead of a count chip.
      height: 15,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      constraints: const BoxConstraints(minWidth: 19),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onThumb ? Colors.white.withValues(alpha: 0.92) : _alertRed,
        borderRadius: BorderRadius.circular(4.5),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: onThumb ? const Color(0xFF5E2126) : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
          height: 1.0,
        ),
      ),
    );
  }
}

// ─── Log row + detail ────────────────────────────────────────────────────────

class _LogTile extends StatefulWidget {
  final DebugLogEntry entry;
  final int? duplicateCount;
  final ValueChanged<DebugLogEntry>? onOpen;
  final ValueChanged<DebugLogEntry>? onTogglePin;
  const _LogTile({
    required this.entry,
    this.duplicateCount,
    this.onOpen,
    this.onTogglePin,
  });

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final dup = widget.duplicateCount;
    final isDup = dup != null && dup > 1;
    final pinned = e.pinned;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color:
            isDup
                ? const Color(0xFF1F1812) // subtle amber wash
                : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          // Pinned outranks duplicate: it is a deliberate user action, and the
          // row needs to stay findable in a wall of amber duplicate warnings.
          color:
              pinned
                  ? const Color(0xFF61AFEF).withValues(alpha: 0.6)
                  : isDup
                  ? const Color(0xFFE5C07B).withValues(alpha: 0.45)
                  : Colors.white10,
          width: pinned || isDup ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            // API rows open the full tabbed detail screen; events expand inline.
            onTap: () {
              if (e.isApi && widget.onOpen != null) {
                widget.onOpen!(e);
              } else {
                setState(() => _expanded = !_expanded);
              }
            },
            // Long-press pins. A per-row pin button would add permanent clutter
            // to every tile for an action used on a handful of them.
            onLongPress:
                widget.onTogglePin == null
                    ? null
                    : () {
                      HapticFeedback.mediumImpact();
                      widget.onTogglePin!(e);
                    },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: e.isApi ? _apiHeader(e) : _eventHeader(e),
            ),
          ),
          if (_expanded && !e.isApi)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  e.isApi ? _apiDetail(e) : _eventDetail(e),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _SectionButton(
                        icon: Icons.delete_outline,
                        label: 'Delete entry',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          DebugLogger.instance.remove(e.id);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Collapsed headers ─────────────────────────────────────────────────────

  Widget _apiHeader(DebugLogEntry e) {
    final origin = _originOf(e.url);
    final path = _pathOf(e.url);
    final query = _queryOf(e.url);
    final errorLine = _apiErrorLine(e);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // Keep badges + chevron level with the first line when the path wraps.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.pinned) ...[const _PinMark(), const SizedBox(width: 5)],
            _MethodBadge(method: e.method ?? '?'),
            const SizedBox(width: 6),
            _StatusBadge(kind: e.kind, statusCode: e.statusCode),
            const SizedBox(width: 8),
            Expanded(child: _EndpointPath(path: path)),
            if (widget.duplicateCount != null &&
                widget.duplicateCount! > 1) ...[
              const SizedBox(width: 6),
              _DuplicateBadge(count: widget.duplicateCount!),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
        // Query parameters get their own decoded chip row so a long query
        // string reads as a legible key/value set instead of a wrapped,
        // percent-encoded blob trailing the path.
        if (query.isNotEmpty) ...[
          const SizedBox(height: 8),
          _QueryParams(params: query),
        ],
        // The origin (scheme://host) on its own full-width line so the complete
        // URL reads end to end — origin here, path above, query as chips —
        // without truncation. The copy button lifts the exact full URL string,
        // the way a network inspector's row does.
        if (origin.isNotEmpty) ...[
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1.5),
                child: Icon(Icons.public, size: 11, color: Colors.white30),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  origin,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
                  softWrap: true,
                ),
              ),
              if (e.url != null)
                _InlineCopyButton(
                  tooltip: 'Copy full URL',
                  onTap: () => _copy(e.url!),
                ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              _time(e.timestamp),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const Spacer(),
            if (e.duration != null) ...[
              Icon(
                Icons.timer_outlined,
                size: 11,
                color: _latencyColor(e.duration!).withValues(alpha: 0.8),
              ),
              const SizedBox(width: 2),
              Text(
                '${e.duration!.inMilliseconds}ms',
                style: TextStyle(
                  color: _latencyColor(e.duration!),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (e.responseBytes != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.download_outlined,
                size: 11,
                color:
                    e.responseBytes! > 512 * 1024
                        ? const Color(0xFFE5C07B)
                        : Colors.white38,
              ),
              const SizedBox(width: 2),
              Text(
                _formatBytes(e.responseBytes!),
                style: TextStyle(
                  color:
                      e.responseBytes! > 512 * 1024
                          ? const Color(0xFFE5C07B)
                          : Colors.white60,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        if (errorLine != null) ...[
          const SizedBox(height: 6),
          _ApiErrorLine(text: errorLine),
        ],
      ],
    );
  }

  Widget _eventHeader(DebugLogEntry e) {
    final color = _kindColor(e.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (e.pinned) ...[const _PinMark(), const SizedBox(width: 5)],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            _kindLabel(e.kind),
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: _expanded ? null : 2,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${_time(e.timestamp)}  ·  ${e.subtitle}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                maxLines: _expanded ? null : 1,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Icon(
          _expanded ? Icons.expand_less : Icons.expand_more,
          color: Colors.white38,
          size: 18,
        ),
      ],
    );
  }

  // ─── Expanded details ─────────────────────────────────────────────────────

  Widget _apiDetail(DebugLogEntry e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Divider(),
        _DetailSection(
          title: 'Overview',
          actions: [
            if (e.url != null)
              _SectionButton(
                icon: Icons.link,
                label: 'URL',
                onTap: () => _copy(e.url!),
              ),
            _SectionButton(
              icon: Icons.terminal,
              label: 'cURL',
              onTap: () => _copy(_buildCurl(e)),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverviewRow(label: 'URL', value: e.url ?? '-'),
              _OverviewRow(label: 'Method', value: e.method ?? '-'),
              _OverviewRow(
                label: 'Status',
                value:
                    e.statusCode != null
                        ? '${e.statusCode} ${_statusText(e.statusCode!)}'
                        : (e.isInFlight ? 'in-flight' : 'error'),
              ),
              if (e.duration != null)
                _OverviewRow(
                  label: 'Duration',
                  value: '${e.duration!.inMilliseconds} ms',
                ),
              if (e.responseBytes != null)
                _OverviewRow(
                  label: 'Size',
                  value: _formatBytes(e.responseBytes!),
                ),
              if (e.errorMessage != null)
                _OverviewRow(
                  label: 'Error',
                  value: e.errorMessage!,
                  valueColor: Colors.redAccent.shade100,
                ),
            ],
          ),
        ),
        if (_hasRequest(e)) ...[
          const SizedBox(height: 10),
          _DetailSection(
            title: 'Request',
            actions: [
              _SectionButton(
                icon: Icons.copy,
                label: 'Copy',
                onTap: () => _copy(_buildRequestText(e)),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.queryParameters != null &&
                    e.queryParameters!.isNotEmpty) ...[
                  const _SubLabel('Query'),
                  _KeyValueList(map: e.queryParameters!),
                  const SizedBox(height: 8),
                ],
                if (e.requestHeaders != null &&
                    e.requestHeaders!.isNotEmpty) ...[
                  const _SubLabel('Headers'),
                  _KeyValueList(map: e.requestHeaders!),
                  const SizedBox(height: 8),
                ],
                if (e.requestBody != null && e.requestBody!.isNotEmpty) ...[
                  const _SubLabel('Body'),
                  _CodeBlock(body: e.requestBody!),
                ],
              ],
            ),
          ),
        ],
        if (_hasResponse(e)) ...[
          const SizedBox(height: 10),
          _DetailSection(
            title: 'Response',
            actions: [
              if (e.responseBody != null && e.responseBody!.isNotEmpty)
                _SectionButton(
                  icon: Icons.copy,
                  label: 'Copy',
                  onTap: () => _copy(e.responseBody!),
                ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.responseHeaders != null &&
                    e.responseHeaders!.isNotEmpty) ...[
                  const _SubLabel('Headers'),
                  _KeyValueList(map: e.responseHeaders!),
                  const SizedBox(height: 8),
                ],
                if (e.responseBody != null && e.responseBody!.isNotEmpty) ...[
                  const _SubLabel('Body'),
                  _CodeBlock(body: e.responseBody!),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _eventDetail(DebugLogEntry e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Divider(),
        if (e.errorMessage != null)
          _DetailSection(
            title: 'Message',
            actions: [
              _SectionButton(
                icon: Icons.copy,
                label: 'Copy',
                onTap: () => _copy(e.errorMessage!),
              ),
            ],
            child: SelectableText(
              e.errorMessage!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        if (e.stackTrace != null) ...[
          const SizedBox(height: 10),
          _DetailSection(
            title: 'Stack trace',
            actions: [
              _SectionButton(
                icon: Icons.copy,
                label: 'Copy',
                onTap: () => _copy(e.stackTrace!),
              ),
            ],
            child: _CodeBlock(body: e.stackTrace!),
          ),
        ],
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  // A one-line, human-readable failure summary for the collapsed API row so a
  // failed call is legible without opening its detail. Prefers the captured
  // error message; otherwise synthesises one from the HTTP status. Returns null
  // for successful / in-flight calls (nothing worth surfacing inline).
  static String? _apiErrorLine(DebugLogEntry e) {
    if (e.kind != DebugLogKind.apiError) return null;
    final msg = e.errorMessage?.trim();
    if (msg != null && msg.isNotEmpty) {
      // Collapse to a single line so the row height stays predictable.
      return msg.replaceAll(RegExp(r'\s+'), ' ');
    }
    final code = e.statusCode;
    if (code != null) {
      final text = _statusText(code);
      return text.isEmpty ? 'HTTP $code' : 'HTTP $code · $text';
    }
    return 'Request failed';
  }

  static bool _hasRequest(DebugLogEntry e) =>
      (e.queryParameters?.isNotEmpty ?? false) ||
      (e.requestHeaders?.isNotEmpty ?? false) ||
      (e.requestBody?.isNotEmpty ?? false);

  static bool _hasResponse(DebugLogEntry e) =>
      (e.responseHeaders?.isNotEmpty ?? false) ||
      (e.responseBody?.isNotEmpty ?? false);

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  static String _hostOf(String? url) {
    if (url == null) return '';
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return '';
    return u.port == 0 || u.port == 80 || u.port == 443
        ? u.host
        : '${u.host}:${u.port}';
  }

  // scheme://host[:port] — the URL's origin, shown in full so the complete
  // request URL is legible from the row. Falls back to the raw string for
  // relative or unparseable URLs.
  static String _originOf(String? url) {
    if (url == null) return '';
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return _hostOf(url);
    final scheme = u.scheme.isEmpty ? '' : '${u.scheme}://';
    return '$scheme${_hostOf(url)}';
  }

  // The endpoint path on its own — query is surfaced separately as chips so the
  // path stays the row's clean, scannable identity.
  static String _pathOf(String? url) {
    if (url == null) return '-';
    final u = Uri.tryParse(url);
    if (u == null) return url;
    return u.path.isEmpty ? '/' : u.path;
  }

  // Decoded query parameters, ready to render as chips. `Uri.queryParameters`
  // already percent-decodes, turning `filter%5Btype%5D=INDEX` into the readable
  // `filter[type] = INDEX`. Empty map when there's no query or it won't parse.
  static Map<String, String> _queryOf(String? url) {
    if (url == null) return const {};
    final u = Uri.tryParse(url);
    if (u == null || u.query.isEmpty) return const {};
    try {
      return u.queryParameters;
    } catch (_) {
      return const {};
    }
  }

  static String _formatBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)}MB';
  }

  // Latency banding so a slow call is obvious in the list without opening it:
  // green ≤300ms, amber ≤1s, red beyond.
  static Color _latencyColor(Duration d) {
    final ms = d.inMilliseconds;
    if (ms <= 300) return const Color(0xFF98C379);
    if (ms <= 1000) return const Color(0xFFE5C07B);
    return const Color(0xFFE06C75);
  }

  static String _buildCurl(DebugLogEntry e) {
    final buf = StringBuffer('curl -X ${e.method ?? "GET"}');
    if (e.requestHeaders != null) {
      for (final h in e.requestHeaders!.entries) {
        buf.write(" -H '${h.key}: ${h.value}'");
      }
    }
    if (e.requestBody != null && e.requestBody!.isNotEmpty) {
      final escaped = e.requestBody!.replaceAll("'", r"'\''");
      buf.write(" --data '$escaped'");
    }
    if (e.url != null) buf.write(" '${e.url}'");
    return buf.toString();
  }

  static String _buildRequestText(DebugLogEntry e) {
    final buf = StringBuffer();
    buf.writeln('${e.method ?? "?"} ${e.url ?? "?"}');
    if (e.queryParameters?.isNotEmpty ?? false) {
      buf.writeln('\n[query]');
      e.queryParameters!.forEach((k, v) => buf.writeln('$k: $v'));
    }
    if (e.requestHeaders?.isNotEmpty ?? false) {
      buf.writeln('\n[headers]');
      e.requestHeaders!.forEach((k, v) => buf.writeln('$k: $v'));
    }
    if (e.requestBody?.isNotEmpty ?? false) {
      buf.writeln('\n[body]');
      buf.writeln(e.requestBody);
    }
    return buf.toString().trim();
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
  }
}

// ─── Reusable building blocks ────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(color: Colors.white12, height: 16, thickness: 1);
}

/// Marks a row the user pinned. Also the only hint that long-press did
/// something, so it sits at the start of the row where the eye lands first.
class _PinMark extends StatelessWidget {
  const _PinMark();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 1),
    child: Icon(Icons.push_pin, size: 12, color: Color(0xFF61AFEF)),
  );
}
