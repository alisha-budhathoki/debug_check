part of 'debug_overlay.dart';

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;

  const _DetailSection({
    required this.title,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1116),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                for (final a in actions) ...[a, const SizedBox(width: 2)],
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SectionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white60, size: 12),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  final String text;
  const _SubLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _OverviewRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValueList extends StatelessWidget {
  final Map<String, String> map;
  const _KeyValueList({required this.map});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: map.entries
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SelectableText.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(
                      text: '${e.key}: ',
                      style: const TextStyle(color: Color(0xFF7EE7E7)),
                    ),
                    TextSpan(
                      text: e.value,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String body;
  const _CodeBlock({required this.body});

  @override
  Widget build(BuildContext context) {
    final pretty = _prettify(body);
    final spans = _highlightJson(pretty);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF05080C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 11.5,
            fontFamily: 'monospace',
            height: 1.4,
            color: Colors.white,
          ),
          children: spans,
        ),
      ),
    );
  }
}

// ─── Method / status badges ──────────────────────────────────────────────────

class _MethodBadge extends StatelessWidget {
  final String method;
  const _MethodBadge({required this.method});

  Color _color() {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF61AFEF); // blue
      case 'POST':
        return const Color(0xFF98C379); // green
      case 'PUT':
        return const Color(0xFFE5C07B); // amber
      case 'PATCH':
        return const Color(0xFFC678DD); // purple
      case 'DELETE':
        return const Color(0xFFE06C75); // red
      default:
        return const Color(0xFFABB2BF); // gray
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final DebugLogKind kind;
  final int? statusCode;
  const _StatusBadge({required this.kind, required this.statusCode});

  Color _color() {
    if (kind == DebugLogKind.apiInFlight) return const Color(0xFFE5C07B);
    final s = statusCode;
    if (s == null) return const Color(0xFFE06C75);
    if (s >= 200 && s < 300) return const Color(0xFF98C379);
    if (s >= 300 && s < 400) return const Color(0xFF61AFEF);
    if (s >= 400 && s < 500) return const Color(0xFFE5C07B);
    return const Color(0xFFE06C75);
  }

  String _label() {
    if (kind == DebugLogKind.apiInFlight) return '⋯';
    return statusCode?.toString() ?? 'ERR';
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    final inFlight = kind == DebugLogKind.apiInFlight;
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child:
          inFlight
              ? SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(c),
                ),
              )
              : Text(
                _label(),
                style: TextStyle(
                  color: c,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
    );
  }
}

// ─── Event kind metadata ─────────────────────────────────────────────────────


