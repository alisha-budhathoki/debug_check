part of 'debug_grid_overlay.dart';

class _RenderHit {
  final RenderBox target;
  final EdgeInsets? padding;
  final List<HitTestEntry> path;

  const _RenderHit({
    required this.target,
    required this.padding,
    required this.path,
  });
}

/// Gap between two rects on each axis (null when they overlap on that axis).
class _Gap {
  final double? horizontal;
  final double? vertical;
  const _Gap(this.horizontal, this.vertical);

  static _Gap between(Rect a, Rect b) {
    double? h;
    if (a.right <= b.left) {
      h = b.left - a.right;
    } else if (b.right <= a.left) {
      h = a.left - b.right;
    }
    double? v;
    if (a.bottom <= b.top) {
      v = b.top - a.bottom;
    } else if (b.bottom <= a.top) {
      v = a.top - b.bottom;
    }
    return _Gap(h, v);
  }
}

_WidgetReport _buildReport(_RenderHit hit, Size screen) {
  final box = hit.target;
  final rect = box.localToGlobal(Offset.zero) & box.size;

  BoxConstraints? constraints;
  try {
    // ignore: invalid_use_of_protected_member
    constraints = box.constraints;
  } catch (_) {}

  var parentOffset = Offset.zero;
  int? flex;
  String? flexFit;
  final pd = box.parentData;
  if (pd is BoxParentData) parentOffset = pd.offset;
  if (pd is FlexParentData) {
    flex = pd.flex;
    flexFit = pd.fit?.name;
  }

  String? text;
  double? fontSize;
  String? fontWeight;
  String? color;
  if (box is RenderParagraph) {
    text = box.text.toPlainText(includeSemanticsLabels: false);
    final st = box.text.style;
    fontSize = st?.fontSize;
    fontWeight = st?.fontWeight?.toString().replaceAll('FontWeight.', '');
    final c = st?.color;
    if (c != null) {
      // ignore: deprecated_member_use
      color = '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }
  }

  final ancestors = <String>[];
  var depth = 0;
  final creator = box.debugCreator;
  if (creator is DebugCreator) {
    creator.element.visitAncestorElements((e) {
      depth++;
      final n = e.widget.runtimeType.toString();
      if (!n.startsWith('_') && ancestors.length < 6) ancestors.add(n);
      return true;
    });
  }

  return _WidgetReport(
    type: _inspectWidgetName(box),
    renderType: box.runtimeType.toString(),
    rect: rect,
    parentOffset: parentOffset,
    constraints: constraints,
    padding: hit.padding,
    flex: flex,
    flexFit: flexFit,
    text: text,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    toEdges: EdgeInsets.fromLTRB(
      rect.left,
      rect.top,
      screen.width - rect.right,
      screen.height - rect.bottom,
    ),
    depth: depth,
    ancestors: ancestors,
  );
}

String _inspectWidgetName(RenderObject r) {
  final creator = r.debugCreator;
  if (creator is DebugCreator) {
    return creator.element.widget.runtimeType.toString();
  }
  return r.runtimeType.toString();
}

/// A padding region: the gap between a widget's edge ([outer]) and its child
/// ([inner]).
@immutable
class _PadBand {
  final Rect outer;
  final Rect inner;
  const _PadBand(this.outer, this.inner);
}

/// De-duplicated geometry for the "Show all bounds" overlay.
class _BoundsData {
  final List<Rect> boxes;
  final List<_PadBand> pads;
  final int signature;

  _BoundsData({required this.boxes, required this.pads})
    : signature = Object.hash(
        boxes.length,
        pads.length,
        // Cheap content fingerprint so we only repaint when geometry changes.
        Object.hashAll(boxes.map((r) => r.hashCode)),
        Object.hashAll(pads.map((p) => p.outer.hashCode ^ p.inner.hashCode)),
      );

  const _BoundsData.empty() : boxes = const [], pads = const [], signature = 0;

  bool get isNotEmpty => boxes.isNotEmpty || pads.isNotEmpty;
}

/// Above this many unique boxes, box hairlines are dropped (padding bands stay)
/// so a very dense screen never turns into a wall of lines.
const int kBoundsEdgeCap = 600;

class _BoundsPainter extends CustomPainter {
  final _BoundsData data;
  _BoundsPainter(this.data);

  static const _edgeColor = Color(0x3326C6DA); // faint cyan hairline
  static const _padFill = Color(0x2600E676); // soft green fill
  static const _padEdge = Color(0x8000E676);

  @override
  void paint(Canvas canvas, Size size) {
    // Padding regions first so they read as filled bands…
    final padFill = Paint()..color = _padFill;
    final padEdge =
        Paint()
          ..color = _padEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75;
    for (final p in data.pads) {
      final band =
          Path()
            ..addRect(p.outer)
            ..addRect(p.inner)
            ..fillType = PathFillType.evenOdd;
      canvas.drawPath(band, padFill);
      canvas.drawRect(p.inner, padEdge);
    }

    // …then thin, faint, de-duplicated box edges on top — but only while the
    // count is low enough to stay readable.
    if (data.boxes.length <= kBoundsEdgeCap) {
      final edge =
          Paint()
            ..color = _edgeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5;
      for (final r in data.boxes) {
        canvas.drawRect(r, edge);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoundsPainter old) =>
      old.data.signature != data.signature;
}

/// Small corner legend shown while "Show all bounds" is active.
class _BoundsLegend extends StatelessWidget {
  final _BoundsData data;
  const _BoundsLegend({required this.data});

  @override
  Widget build(BuildContext context) {
    final edgesHidden = data.boxes.length > kBoundsEdgeCap;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: 12,
      bottom: bottom + 12,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xF20E1116),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _swatch(const Color(0x9900E676), 'padding · ${data.pads.length}'),
              const SizedBox(height: 4),
              _swatch(
                const Color(0x9926C6DA),
                edgesHidden
                    ? 'box edges hidden · ${data.boxes.length} (dense)'
                    : 'box edges · ${data.boxes.length}',
                muted: edgesHidden,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(Color color, String label, {bool muted = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: muted ? Colors.white38 : Colors.white70,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
