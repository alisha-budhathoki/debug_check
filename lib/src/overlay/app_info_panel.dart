part of 'debug_overlay.dart';

class _AppInfoPanel extends StatefulWidget {
  const _AppInfoPanel();

  @override
  State<_AppInfoPanel> createState() => _AppInfoPanelState();
}

class _AppInfoPanelState extends State<_AppInfoPanel> {
  late AppInfoSnapshot _info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _info = AppInfoSnapshot.capture(context);
  }

  Future<void> _copyAll() async {
    final text =
        '${_info.toReadableText()}\n${_apiStats(DebugLogger.instance.entries.value).toReadableText()}';
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.lightImpact();
  }

  void _refresh() {
    setState(() => _info = AppInfoSnapshot.capture(context));
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Snapshot — paste in bug reports',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _SectionButton(
              icon: Icons.refresh,
              label: 'Refresh',
              onTap: _refresh,
            ),
            const SizedBox(width: 4),
            _SectionButton(
              icon: Icons.copy_all,
              label: 'Copy all',
              onTap: _copyAll,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DetailSection(
          title: 'App',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverviewRow(label: 'Version', value: info.version),
              _OverviewRow(
                label: 'Build',
                value: info.buildMode,
                valueColor: _buildModeColor(info.buildMode),
              ),
              _OverviewRow(
                label: 'Environment',
                value: info.environment,
                valueColor:
                    info.environment == 'live'
                        ? const Color(0xFFE5C07B)
                        : const Color(0xFF98C379),
              ),
              _OverviewRow(label: 'Base URL', value: info.baseUrl),
              _OverviewRow(
                label: 'isNativeCall',
                value: info.isNativeCall.toString(),
              ),
              _OverviewRow(
                label: 'Launched from',
                value: info.launchSourceLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Live API stats — listens directly so values update while panel is open.
        ValueListenableBuilder<List<DebugLogEntry>>(
          valueListenable: DebugLogger.instance.entries,
          builder: (context, entries, _) {
            final s = _apiStats(entries);
            final dupes = findDuplicateApiCalls(entries);
            final dupEntries = dupes.length;
            return _DetailSection(
              title: 'API stats',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OverviewRow(label: 'Total', value: s.total.toString()),
                  _OverviewRow(
                    label: 'Success',
                    value: s.success.toString(),
                    valueColor: const Color(0xFF98C379),
                  ),
                  _OverviewRow(
                    label: 'Errors',
                    value: s.errors.toString(),
                    valueColor: s.errors > 0 ? const Color(0xFFE06C75) : null,
                  ),
                  _OverviewRow(
                    label: 'In-flight',
                    value: s.inFlight.toString(),
                    valueColor: s.inFlight > 0 ? const Color(0xFFE5C07B) : null,
                  ),
                  _OverviewRow(
                    label: 'Duplicates',
                    value:
                        dupEntries == 0
                            ? '0'
                            : '$dupEntries identical '
                                'call${dupEntries == 1 ? "" : "s"}',
                    valueColor: dupEntries > 0 ? const Color(0xFFE5C07B) : null,
                  ),
                  _OverviewRow(
                    label: 'Avg time',
                    value: s.avgMs == null ? '-' : '${s.avgMs} ms',
                  ),
                  _OverviewRow(
                    label: 'Slowest',
                    value:
                        s.slowest == null
                            ? '-'
                            : '${s.slowestMs} ms · ${s.slowest}',
                  ),
                  _OverviewRow(
                    label: 'Last call',
                    value: s.lastCallTime ?? '-',
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        // Live error summary.
        ValueListenableBuilder<List<DebugLogEntry>>(
          valueListenable: DebugLogger.instance.entries,
          builder: (context, entries, _) {
            final errs = entries
                .where((e) => e.isError)
                .toList(growable: false);
            final last = errs.isEmpty ? null : errs.first;
            return _DetailSection(
              title: 'Errors',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OverviewRow(
                    label: 'Total',
                    value: errs.length.toString(),
                    valueColor:
                        errs.isEmpty
                            ? const Color(0xFF98C379)
                            : const Color(0xFFE06C75),
                  ),
                  if (last != null) ...[
                    _OverviewRow(
                      label: 'Last at',
                      value: _formatTimeShort(last.timestamp),
                    ),
                    _OverviewRow(label: 'Last kind', value: last.kind.name),
                    _OverviewRow(label: 'Last msg', value: last.subtitle),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _DetailSection(
          title: 'Platform',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverviewRow(label: 'OS', value: '${info.os}  ${info.osVersion}'),
              _OverviewRow(label: 'Dart', value: info.dartVersion),
              _OverviewRow(label: 'CPUs', value: info.processors.toString()),
              _OverviewRow(label: 'Locale', value: info.localeName),
              _OverviewRow(label: 'Time zone', value: info.timeZoneName),
              _OverviewRow(
                label: '24h time',
                value: info.alwaysUse24HourFormat.toString(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _DetailSection(
          title: 'Display',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverviewRow(
                label: 'Screen',
                value:
                    '${info.screenSize.width.toStringAsFixed(0)}'
                    '×${info.screenSize.height.toStringAsFixed(0)} '
                    '@${info.devicePixelRatio.toStringAsFixed(2)}x',
              ),
              _OverviewRow(label: 'Orientation', value: info.orientation),
              _OverviewRow(label: 'Brightness', value: info.brightness),
              _OverviewRow(
                label: 'Text scale',
                value: '${info.textScale.toStringAsFixed(2)}x',
              ),
              _OverviewRow(
                label: 'Safe area',
                value:
                    't=${info.safeAreaPadding.top.toStringAsFixed(0)} '
                    'b=${info.safeAreaPadding.bottom.toStringAsFixed(0)} '
                    'l=${info.safeAreaPadding.left.toStringAsFixed(0)} '
                    'r=${info.safeAreaPadding.right.toStringAsFixed(0)}',
              ),
              _OverviewRow(
                label: 'Keyboard',
                value:
                    info.keyboardVisible
                        ? 'visible (${info.viewInsets.bottom.toStringAsFixed(0)}px)'
                        : 'hidden',
                valueColor:
                    info.keyboardVisible ? const Color(0xFF61AFEF) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _DetailSection(
          title: 'Accessibility',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverviewRow(
                label: 'Bold text',
                value: info.boldText.toString(),
                valueColor: info.boldText ? const Color(0xFFE5C07B) : null,
              ),
              _OverviewRow(
                label: 'High contrast',
                value: info.highContrast.toString(),
                valueColor: info.highContrast ? const Color(0xFFE5C07B) : null,
              ),
              _OverviewRow(
                label: 'Invert colors',
                value: info.invertColors.toString(),
                valueColor: info.invertColors ? const Color(0xFFE5C07B) : null,
              ),
              _OverviewRow(
                label: 'Disable anims',
                value: info.disableAnimations.toString(),
                valueColor:
                    info.disableAnimations ? const Color(0xFFE5C07B) : null,
              ),
              _OverviewRow(
                label: 'A11y nav',
                value: info.accessibleNavigation.toString(),
                valueColor:
                    info.accessibleNavigation ? const Color(0xFFE5C07B) : null,
              ),
              if (info.hasAccessibilityOverrides)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '⚠ user has accessibility overrides active — '
                    'reproduce bugs with these settings',
                    style: TextStyle(
                      color: Color(0xFFE5C07B),
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _DetailSection(
          title: 'Runtime',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverviewRow(label: 'Lifecycle', value: info.lifecycleState),
              _OverviewRow(
                label: 'Started',
                value: info.appStartedAt.toIso8601String(),
              ),
              _OverviewRow(label: 'Uptime', value: info.uptimeReadable),
              _OverviewRow(
                label: 'Captured',
                value: info.capturedAt.toIso8601String(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _buildModeColor(String mode) {
    switch (mode) {
      case 'RELEASE':
        return const Color(0xFF98C379);
      case 'PROFILE':
        return const Color(0xFF61AFEF);
      default:
        return const Color(0xFFE5C07B);
    }
  }

  static String _formatTimeShort(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

class _ApiStats {
  final int total;
  final int success;
  final int errors;
  final int inFlight;
  final int? avgMs;
  final String? slowest;
  final int? slowestMs;
  final String? lastCallTime;

  const _ApiStats({
    required this.total,
    required this.success,
    required this.errors,
    required this.inFlight,
    required this.avgMs,
    required this.slowest,
    required this.slowestMs,
    required this.lastCallTime,
  });

  String toReadableText() {
    final buf = StringBuffer();
    buf.writeln('━━━ API STATS ━━━');
    buf.writeln('Total: $total');
    buf.writeln('Success: $success');
    buf.writeln('Errors: $errors');
    buf.writeln('In-flight: $inFlight');
    buf.writeln('Avg time: ${avgMs ?? "-"} ms');
    if (slowest != null) buf.writeln('Slowest: $slowestMs ms · $slowest');
    if (lastCallTime != null) buf.writeln('Last call: $lastCallTime');
    return buf.toString();
  }
}

_ApiStats _apiStats(List<DebugLogEntry> entries) {
  final apis = entries.where((e) => e.isApi).toList(growable: false);
  int success = 0, errors = 0, inFlight = 0;
  int durSum = 0, durCount = 0;
  DebugLogEntry? slowestEntry;
  int slowestMs = -1;
  for (final e in apis) {
    switch (e.kind) {
      case DebugLogKind.apiSuccess:
        success++;
        break;
      case DebugLogKind.apiError:
        errors++;
        break;
      case DebugLogKind.apiInFlight:
        inFlight++;
        break;
      default:
        break;
    }
    final d = e.duration;
    if (d != null) {
      durSum += d.inMilliseconds;
      durCount++;
      if (d.inMilliseconds > slowestMs) {
        slowestMs = d.inMilliseconds;
        slowestEntry = e;
      }
    }
  }
  final last = apis.isEmpty ? null : apis.first;
  return _ApiStats(
    total: apis.length,
    success: success,
    errors: errors,
    inFlight: inFlight,
    avgMs: durCount == 0 ? null : durSum ~/ durCount,
    slowest:
        slowestEntry == null
            ? null
            : '${slowestEntry.method ?? "?"} ${_shortPath(slowestEntry.url)}',
    slowestMs: slowestEntry == null ? null : slowestMs,
    lastCallTime:
        last == null
            ? null
            : '${last.timestamp.hour.toString().padLeft(2, '0')}:'
                '${last.timestamp.minute.toString().padLeft(2, '0')}:'
                '${last.timestamp.second.toString().padLeft(2, '0')}',
  );
}

String _shortPath(String? url) {
  if (url == null) return '-';
  final u = Uri.tryParse(url);
  if (u == null) return url;
  final p = u.path.isEmpty ? '/' : u.path;
  return p.length > 40 ? '${p.substring(0, 37)}…' : p;
}
