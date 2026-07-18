part of 'debug_overlay.dart';

/// Offers the whole-session artefacts. Kept to a sheet of explicit choices
/// rather than one "Export" button, because the three outputs answer different
/// questions and pasting a 400-line HAR into a GitHub issue helps nobody.
Future<void> _showSessionExport(
  BuildContext context,
  List<DebugLogEntry> entries,
) async {
  HapticFeedback.selectionClick();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _SessionExportSheet(entries: entries),
  );
}

class _SessionExportSheet extends StatelessWidget {
  final List<DebugLogEntry> entries;
  const _SessionExportSheet({required this.entries});

  Future<void> _copy(BuildContext context, String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.lightImpact();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final perf = PerfMonitor.instance.stats.value;
    final api = entries.where((e) => e.isApi).length;
    final errors = entries.where((e) => e.isError).length;

    return Theme(
      data: _kDebugOverlayTheme,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12171F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Export session',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entries.length} entries · $api requests · '
                      '$errors errors',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _ExportOption(
                icon: Icons.description_outlined,
                title: 'Bug report (Markdown)',
                subtitle:
                    'Grade, environment, failures and the trail that led '
                    'there — paste into an issue or PR',
                onTap:
                    () => _copy(
                      context,
                      SessionExport.toMarkdown(
                        entries: entries,
                        perf: perf,
                        appInfo: AppInfoSnapshot.capture(context),
                      ),
                      'report',
                    ),
              ),
              _ExportOption(
                icon: Icons.archive_outlined,
                title: 'Network archive (HAR)',
                subtitle: 'Every request, for a HAR viewer or browser devtools',
                enabled: api > 0,
                onTap:
                    () => _copy(
                      context,
                      SessionExport.toHar(entries: entries),
                      'HAR',
                    ),
              ),
              _ExportOption(
                icon: Icons.local_hospital_outlined,
                title: 'Autopsy only',
                subtitle: 'Just the diagnosis, no traffic',
                onTap:
                    () => _copy(
                      context,
                      AppAutopsy.diagnose(
                        entries: entries,
                        perf: perf,
                      ).toMarkdown(),
                      'autopsy',
                    ),
              ),
              const SizedBox(height: 8),
              if (DebugTools.redaction.canReveal &&
                  DebugTools.revealSecrets.value)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Color(0xFFE5C07B),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        // Loud, because this is the moment a revealed secret
                        // actually escapes the device.
                        child: Text(
                          'Secrets are revealed — this export will contain '
                          'real credentials.',
                          style: TextStyle(
                            color: Color(0xFFE5C07B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 19, color: const Color(0xFF61AFEF)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.copy_rounded, size: 14, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
