part of 'debug_grid_overlay.dart';

@immutable
class _Inspection {
  final Rect rect;
  final EdgeInsets? padding;
  final String name;

  const _Inspection({
    required this.rect,
    required this.padding,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      other is _Inspection &&
      other.rect == rect &&
      other.padding == padding &&
      other.name == name;

  @override
  int get hashCode => Object.hash(rect, padding, name);
}

class _InspectPainter extends CustomPainter {
  final _Inspection current;
  final _Inspection? previous;
  _InspectPainter({required this.current, this.previous});

  static const _boxColor = Color(0xFF4FC3F7); // blue — matches the control bar
  static const _padColor = Color(0xFF00E676); // green — padding
  static const _anchorColor = Color(0xFFFFB74D); // amber — measure anchor
  static const _measureColor = Color(0xFFFFD54F); // amber — measure line

  @override
  void paint(Canvas canvas, Size size) {
    final rect = current.rect;

    // Dim everything except the inspected widget so it stands out.
    final dim =
        Path()
          ..addRect(Offset.zero & size)
          ..addRect(rect)
          ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x33000000));

    // Measure anchor (previously tapped widget) + gap lines.
    final prev = previous;
    if (prev != null && prev.rect != rect) {
      canvas.drawRect(
        prev.rect,
        Paint()
          ..color = _anchorColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      _drawMeasure(canvas, size, prev.rect, rect);
    }

    // Padding band (green) between the widget edge and its content.
    final p = current.padding;
    if (p != null && p != EdgeInsets.zero) {
      final inner = Rect.fromLTRB(
        rect.left + p.left,
        rect.top + p.top,
        rect.right - p.right,
        rect.bottom - p.bottom,
      );
      if (inner.width > 0 && inner.height > 0) {
        final band =
            Path()
              ..addRect(rect)
              ..addRect(inner)
              ..fillType = PathFillType.evenOdd;
        canvas.drawPath(
          band,
          Paint()..color = _padColor.withValues(alpha: 0.20),
        );
        canvas.drawRect(
          inner,
          Paint()
            ..color = _padColor.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // Widget bounds.
    canvas.drawRect(
      rect,
      Paint()
        ..color = _boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Dimension badge above (or inside) the box.
    final label =
        '${rect.width.toStringAsFixed(1)} × ${rect.height.toStringAsFixed(1)}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final badgeW = tp.width + 10;
    final badgeH = tp.height + 6;
    var bx = rect.left;
    var by = rect.top - badgeH - 2;
    if (by < 0) by = rect.top + 2; // flip inside if no room above
    if (bx + badgeW > size.width) bx = size.width - badgeW;
    if (bx < 0) bx = 0;
    final badgeRect = Rect.fromLTWH(bx, by, badgeW, badgeH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
      Paint()..color = _boxColor,
    );
    tp.paint(canvas, Offset(bx + 5, by + 3));
  }

  /// Draws the gap measurement between the anchor [a] and current [b] rects.
  void _drawMeasure(Canvas canvas, Size size, Rect a, Rect b) {
    final gap = _Gap.between(a, b);
    final line =
        Paint()
          ..color = _measureColor
          ..strokeWidth = 1;

    final v = gap.vertical;
    if (v != null && v > 0.5) {
      final y1 = a.bottom <= b.top ? a.bottom : b.bottom;
      final y2 = a.bottom <= b.top ? b.top : a.top;
      // Place the line where the two rects overlap horizontally, else mid b.
      final ovL = math.max(a.left, b.left);
      final ovR = math.min(a.right, b.right);
      final x = ovL <= ovR ? (ovL + ovR) / 2 : b.center.dx;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), line);
      _measureLabel(canvas, v, Offset(x, (y1 + y2) / 2));
    }

    final h = gap.horizontal;
    if (h != null && h > 0.5) {
      final x1 = a.right <= b.left ? a.right : b.right;
      final x2 = a.right <= b.left ? b.left : a.left;
      final ovT = math.max(a.top, b.top);
      final ovB = math.min(a.bottom, b.bottom);
      final y = ovT <= ovB ? (ovT + ovB) / 2 : b.center.dy;
      canvas.drawLine(Offset(x1, y), Offset(x2, y), line);
      _measureLabel(canvas, h, Offset((x1 + x2) / 2, y));
    }
  }

  void _measureLabel(Canvas canvas, double value, Offset center) {
    final tp = TextPainter(
      text: TextSpan(
        text: '${value.toStringAsFixed(1)}px',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 8,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = _measureColor,
    );
    tp.paint(canvas, Offset(rect.left + 4, rect.top + 2));
  }

  @override
  bool shouldRepaint(covariant _InspectPainter old) =>
      old.current != current || old.previous != previous;
}

/// Compact detail card pinned near the inspected box. Also shows the measured
/// gap to the previously tapped widget. Only shown once something is selected.
class _InspectHud extends StatelessWidget {
  final _Inspection current;
  final _Inspection? previous;

  const _InspectHud({required this.current, this.previous});

  static const _accent = Color(0xFF4FC3F7);

  @override
  Widget build(BuildContext context) {
    final ins = current;
    final screen = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;

    const cardW = 220.0;
    const cardH = 118.0;
    final left = ins.rect.left.clamp(8.0, screen.width - cardW - 8);
    var top = ins.rect.bottom + 8;
    if (top + cardH > screen.height - 8) {
      top = (ins.rect.top - cardH - 8).clamp(
        safeTop + 8,
        screen.height - cardH - 8,
      );
    }

    return Positioned(left: left, top: top, width: cardW, child: _card(ins));
  }

  Widget _card(_Inspection ins) {
    final p = ins.padding;
    final padText =
        (p == null || p == EdgeInsets.zero)
            ? 'none'
            : 'L${_n(p.left)} T${_n(p.top)} R${_n(p.right)} B${_n(p.bottom)}';

    final prev = previous;
    String? gapText;
    if (prev != null && prev.rect != ins.rect) {
      final g = _Gap.between(prev.rect, ins.rect);
      final parts = <String>[
        if (g.horizontal != null && g.horizontal! > 0.5)
          '↔ ${_n(g.horizontal!)}',
        if (g.vertical != null && g.vertical! > 0.5) '↕ ${_n(g.vertical!)}',
      ];
      gapText = parts.isEmpty ? 'adjacent' : '${parts.join('  ')} px';
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xF2141A21),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ins.name,
              style: const TextStyle(
                color: _accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            _row('Size', '${_n(ins.rect.width)} × ${_n(ins.rect.height)}'),
            _row('Offset', '${_n(ins.rect.left)}, ${_n(ins.rect.top)}'),
            _row('Padding', padText, color: const Color(0xFF00E676)),
            if (gapText != null)
              _row('Gap', gapText, color: const Color(0xFFFFD54F)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _n(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
}

// ─── Long-press detail report ────────────────────────────────────────────────

/// Full snapshot of a widget for the long-press "assistant" sheet.
