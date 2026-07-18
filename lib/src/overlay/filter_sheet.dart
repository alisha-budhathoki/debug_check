part of 'debug_overlay.dart';

/// The secondary-filter sheet: category, status class, method and pinned-only.
///
/// Edits a local copy and only returns it on Apply, so backing out with the
/// scrim leaves the list exactly as it was — filters are easy to set by
/// accident and annoying to reconstruct.
class _FilterSheet extends StatefulWidget {
  final LogFilter initial;
  final List<DebugLogEntry> entries;
  const _FilterSheet({required this.initial, required this.entries});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late LogFilter _draft = widget.initial;

  /// Live count of what Apply would leave on screen. Turning a filter on and
  /// landing on an empty list is the main way these go wrong, so the answer is
  /// shown before committing rather than after.
  int get _matchCount => widget.entries.where(_draft.matches).length;

  Set<T> _toggled<T>(Set<T> set, T value) {
    final next = Set<T>.of(set);
    next.contains(value) ? next.remove(value) : next.add(value);
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final methods = LogFilter.methodsIn(widget.entries);
    final pinnedCount = widget.entries.where((e) => e.pinned).length;

    return Theme(
      data: _kDebugOverlayTheme,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12171F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
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
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                child: Row(
                  children: [
                    const Text(
                      'Filter logs',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (!_draft.isEmpty)
                      TextButton(
                        onPressed:
                            () => setState(() => _draft = LogFilter.none),
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                            color: Color(0xFF61AFEF),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _group(
                        'Type',
                        [
                          for (final c in LogCategory.values)
                            _chip(
                              label: c.label,
                              selected: _draft.categories.contains(c),
                              onTap:
                                  () => setState(
                                    () =>
                                        _draft = _draft.copyWith(
                                          categories: _toggled(
                                            _draft.categories,
                                            c,
                                          ),
                                        ),
                                  ),
                            ),
                        ],
                        // Events == breadcrumbs. Named for what the user
                        // dropped, not the DebugLogKind it maps to.
                        hint: 'Events are your breadcrumbs',
                      ),
                      _group('Status', [
                        for (final s in StatusClass.values)
                          _chip(
                            label: s.label,
                            selected: _draft.statusClasses.contains(s),
                            onTap:
                                () => setState(
                                  () =>
                                      _draft = _draft.copyWith(
                                        statusClasses: _toggled(
                                          _draft.statusClasses,
                                          s,
                                        ),
                                      ),
                                ),
                          ),
                      ], hint: 'Applies to API calls only'),
                      if (methods.isNotEmpty)
                        _group('Method', [
                          for (final m in methods)
                            _chip(
                              label: m,
                              selected: _draft.methods.contains(m),
                              onTap:
                                  () => setState(
                                    () =>
                                        _draft = _draft.copyWith(
                                          methods: _toggled(_draft.methods, m),
                                        ),
                                  ),
                            ),
                        ]),
                      _group(
                        'Pinned',
                        [
                          _chip(
                            label:
                                pinnedCount > 0
                                    ? 'Pinned only ($pinnedCount)'
                                    : 'Pinned only',
                            selected: _draft.pinnedOnly,
                            onTap:
                                () => setState(
                                  () =>
                                      _draft = _draft.copyWith(
                                        pinnedOnly: !_draft.pinnedOnly,
                                      ),
                                ),
                          ),
                        ],
                        hint: 'Pinned entries also survive the 200-entry cap',
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2A5D8F),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: Text(
                      _draft.isEmpty
                          ? 'Show all logs'
                          : 'Show $_matchCount of ${widget.entries.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> chips, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: chips),
      ],
    ),
  );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1E3A52) : const Color(0xFF1A1F27),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color:
              selected
                  ? const Color(0xFF61AFEF)
                  : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF9CD1FF) : Colors.white60,
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    ),
  );
}
