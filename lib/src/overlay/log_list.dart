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
  String _filter = 'all'; // all | api | errors | info
  String _search = '';
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
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return e.title.toLowerCase().contains(q) ||
        (e.url?.toLowerCase().contains(q) ?? false) ||
        (e.errorMessage?.toLowerCase().contains(q) ?? false);
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

    final isInfoTab = _filter == 'info';
    final isGridTab = _filter == 'grid';
    final isPerfTab = _filter == 'perf';
    // Info, Grid and Perf are control panels, not log lists.
    final isPanelTab = isInfoTab || isGridTab || isPerfTab;
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
              searchCtrl: _searchCtrl,
              onSearchChanged: (v) => setState(() => _search = v),
              showSearch: !isPanelTab,
            ),
            if (!isPanelTab && dupeRows > 0)
              _DuplicateWarningBar(count: dupeRows),
            Expanded(
              child:
                  isGridTab
                      ? const DebugGridPanel()
                      : isPerfTab
                      ? const _PerfPanel()
                      : isInfoTab
                      ? const _AppInfoPanel()
                      : filtered.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) {
                          final entry = filtered[i];
                          return _LogTile(
                            entry: entry,
                            duplicateCount: dupes[entry.id],
                            onOpen: (e) => setState(() => _detailId = e.id),
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
              '(identical method, path, params & body within 5s)',
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

/// Detects API entries that share an identical request — method, path, query
/// parameters AND request body — with another entry within [window]. A matching
/// endpoint alone is not enough; everything must be the same. Returns id →
/// cluster size (always ≥ 2 for entries that have a duplicate). Entries with
/// cluster size 1 (no duplicates) are omitted.
///
/// Complexity: O(n) — single pass grouping + linear cluster sweep.
Map<int, int> findDuplicateApiCalls(
  List<DebugLogEntry> entries, {
  Duration window = const Duration(seconds: 5),
}) {
  final byKey = <String, List<DebugLogEntry>>{};
  for (final e in entries) {
    if (!e.isApi || e.url == null || e.method == null) continue;
    final uri = Uri.tryParse(e.url!);
    final path =
        uri?.path.isNotEmpty == true ? uri!.path : (uri?.toString() ?? e.url!);
    // Merge query params from the URL and the explicit map, then sort so that
    // ordering differences don't affect the key.
    final query = <String, String>{
      ...?uri?.queryParameters,
      ...?e.queryParameters,
    };
    final sortedQuery = (query.keys.toList()..sort())
        .map((k) => '$k=${query[k]}')
        .join('&');
    // A request is only a duplicate when method, path, query params AND body
    // all match — endpoint alone is not enough.
    final key = '${e.method}|$path|$sortedQuery|${e.requestBody ?? ''}';
    byKey.putIfAbsent(key, () => []).add(e);
  }

  final result = <int, int>{};
  for (final group in byKey.values) {
    if (group.length < 2) continue;
    // Sort oldest → newest so we can use a sliding window.
    group.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (var i = 0; i < group.length; i++) {
      int clusterSize = 1;
      // count backwards while still within window
      for (var j = i - 1; j >= 0; j--) {
        if (group[i].timestamp.difference(group[j].timestamp) > window) break;
        clusterSize++;
      }
      // count forwards while still within window
      for (var j = i + 1; j < group.length; j++) {
        if (group[j].timestamp.difference(group[i].timestamp) > window) break;
        clusterSize++;
      }
      if (clusterSize > 1) result[group[i].id] = clusterSize;
    }
  }
  return result;
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
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final bool showSearch;

  const _ViewerHeader({
    required this.filter,
    required this.onFilterChange,
    required this.onClear,
    required this.onMinimize,
    required this.onClose,
    required this.onHide,
    required this.total,
    required this.shown,
    required this.searchCtrl,
    required this.onSearchChanged,
    this.showSearch = true,
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
          if (showSearch) ...[
            const SizedBox(height: 8),
            _SearchField(controller: searchCtrl, onChanged: onSearchChanged),
          ],
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: filter == 'all',
                  onTap: () => onFilterChange('all'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'API',
                  selected: filter == 'api',
                  onTap: () => onFilterChange('api'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Errors',
                  selected: filter == 'errors',
                  onTap: () => onFilterChange('errors'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Info',
                  selected: filter == 'info',
                  onTap: () => onFilterChange('info'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Perf',
                  selected: filter == 'perf',
                  onTap: () => onFilterChange('perf'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Grid',
                  selected: filter == 'grid',
                  onTap: () => onFilterChange('grid'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1116),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        cursorColor: Colors.white70,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: InputBorder.none,
          hintText: 'Search URL, error, title…',
          hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
          prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 0),
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.white : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
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
  const _LogTile({required this.entry, this.duplicateCount, this.onOpen});

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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color:
            isDup
                ? const Color(0xFF1F1812) // subtle amber wash
                : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isDup
                  ? const Color(0xFFE5C07B).withValues(alpha: 0.45)
                  : Colors.white10,
          width: isDup ? 1.2 : 1,
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
    final host = _hostOf(e.url);
    final path = _pathOf(e.url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _MethodBadge(method: e.method ?? '?'),
            const SizedBox(width: 6),
            _StatusBadge(kind: e.kind, statusCode: e.statusCode),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.duplicateCount != null &&
                widget.duplicateCount! > 1) ...[
              const SizedBox(width: 6),
              _DuplicateBadge(count: widget.duplicateCount!),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
        const SizedBox(height: 4),
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
            const Text(
              '  ·  ',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
            Flexible(
              child: Text(
                host,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
      ],
    );
  }

  Widget _eventHeader(DebugLogEntry e) {
    final color = _kindColor(e.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  static String _pathOf(String? url) {
    if (url == null) return '-';
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final path = u.path.isEmpty ? '/' : u.path;
    return u.query.isEmpty ? path : '$path?${u.query}';
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


