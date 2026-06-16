part of 'debug_grid_overlay.dart';

class _WidgetReport {
  final String type;
  final String renderType;
  final Rect rect;
  final Offset parentOffset;
  final BoxConstraints? constraints;
  final EdgeInsets? padding;
  final int? flex;
  final String? flexFit;
  final String? text;
  final double? fontSize;
  final String? fontWeight;
  final String? color;
  final EdgeInsets toEdges;
  final int depth;
  final List<String> ancestors;

  const _WidgetReport({
    required this.type,
    required this.renderType,
    required this.rect,
    required this.parentOffset,
    required this.constraints,
    required this.padding,
    required this.flex,
    required this.flexFit,
    required this.text,
    required this.fontSize,
    required this.fontWeight,
    required this.color,
    required this.toEdges,
    required this.depth,
    required this.ancestors,
  });

  static String _n(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

  String get sizeText => '${_n(rect.width)} × ${_n(rect.height)}';
  String get positionText => '${_n(rect.left)}, ${_n(rect.top)}';
  String get inParentText => '${_n(parentOffset.dx)}, ${_n(parentOffset.dy)}';

  String? get paddingText {
    final p = padding;
    if (p == null || p == EdgeInsets.zero) return null;
    return 'L${_n(p.left)} T${_n(p.top)} R${_n(p.right)} B${_n(p.bottom)}';
  }

  String? get constraintsText {
    final c = constraints;
    if (c == null) return null;
    String r(double mn, double mx) {
      final lo = mn.isFinite ? _n(mn) : '0';
      final hi = mx.isFinite ? _n(mx) : '∞';
      return '$lo–$hi';
    }

    return 'W ${r(c.minWidth, c.maxWidth)}   H ${r(c.minHeight, c.maxHeight)}';
  }

  String get edgesText =>
      'L${_n(toEdges.left)} T${_n(toEdges.top)} '
      'R${_n(toEdges.right)} B${_n(toEdges.bottom)}';

  String? get textStyleText {
    if (text == null) return null;
    final parts = <String>[
      if (fontSize != null) '${_n(fontSize!)}px',
      if (fontWeight != null) 'w$fontWeight',
      if (color != null) color!,
    ];
    return parts.isEmpty ? null : parts.join('  ');
  }

  /// Plain-text dump for the Copy button (QA can paste into tickets).
  String toReadableText() {
    final b =
        StringBuffer()
          ..writeln('Widget: $type')
          ..writeln('Render: $renderType')
          ..writeln('Depth: $depth')
          ..writeln('Size: $sizeText')
          ..writeln('Position: $positionText')
          ..writeln('In parent: $inParentText');
    if (constraintsText != null) b.writeln('Constraints: $constraintsText');
    if (paddingText != null) b.writeln('Padding: $paddingText');
    if (flex != null) b.writeln('Flex: $flex (${flexFit ?? '-'})');
    if (textStyleText != null) b.writeln('Text style: $textStyleText');
    if (text != null && text!.trim().isNotEmpty) {
      b.writeln('Text: "${text!.trim()}"');
    }
    b.writeln('To screen edges: $edgesText');
    if (ancestors.isNotEmpty) b.writeln('Ancestors: ${ancestors.join(' › ')}');
    return b.toString();
  }
}

/// Bottom sheet that lays out a [_WidgetReport] for QA / managers / devs.
class _ReportSheet extends StatelessWidget {
  final _WidgetReport report;
  final VoidCallback onClose;

  const _ReportSheet({required this.report, required this.onClose});

  static const _accent = Color(0xFF00E5FF);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: report.toReadableText()));
    await HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final r = report;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxHeight: screen.height * 0.5),
          padding: EdgeInsets.only(bottom: bottom + 8),
          decoration: const BoxDecoration(
            color: Color(0xF20E1116),
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(top: BorderSide(color: _accent, width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.widgets_outlined,
                      color: _accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.type,
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _headerBtn(Icons.copy_all, 'Copy', _copy),
                    const SizedBox(width: 4),
                    _headerBtn(Icons.close, 'Close', onClose),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  children: [
                    _section('Identity', [
                      _kv('Render object', r.renderType),
                      _kv('Tree depth', '${r.depth}'),
                    ]),
                    _section('Geometry', [
                      _kv('Size', r.sizeText),
                      _kv('Position', r.positionText),
                      _kv('In parent', r.inParentText),
                      _kv('To edges', r.edgesText),
                    ]),
                    if (r.constraintsText != null)
                      _section('Constraints', [
                        _kv('Given', r.constraintsText!),
                      ]),
                    if (r.paddingText != null || r.flex != null)
                      _section('Layout', [
                        if (r.paddingText != null)
                          _kv('Padding', r.paddingText!, accent: _green),
                        if (r.flex != null)
                          _kv('Flex', '${r.flex} (${r.flexFit ?? '-'})'),
                      ]),
                    if (r.text != null && r.text!.trim().isNotEmpty)
                      _section('Text', [
                        if (r.textStyleText != null)
                          _kv('Style', r.textStyleText!),
                        _kv('Content', '"${r.text!.trim()}"'),
                      ]),
                    if (r.ancestors.isNotEmpty)
                      _section('Ancestors', [
                        _kv('Chain', r.ancestors.join('  ›  ')),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _green = Color(0xFF00E676);

  Widget _headerBtn(IconData icon, String label, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  Widget _kv(String key, String value, {Color? accent}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              key,
              style: const TextStyle(color: Colors.white38, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: accent ?? Colors.white,
                fontSize: 12.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Floating inspect control ────────────────────────────────────────────────

/// Clean, draggable control bar shown while inspect mode is on: a single
/// Inspect⇄Browse segmented toggle, a state-aware hint, and clear / exit — all
/// in one neutral surface with a single accent, so enabling inspect doesn't
/// drop a pile of colourful chips on screen.

