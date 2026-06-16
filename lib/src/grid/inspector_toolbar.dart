part of 'debug_grid_overlay.dart';

class _InspectToolbar extends StatefulWidget {
  final bool pickMode;
  final String hint;
  final bool hasSelection;
  final ValueChanged<bool> onSetMode;
  final VoidCallback onClear;
  final VoidCallback onClose;

  const _InspectToolbar({
    required this.pickMode,
    required this.hint,
    required this.hasSelection,
    required this.onSetMode,
    required this.onClear,
    required this.onClose,
  });

  @override
  State<_InspectToolbar> createState() => _InspectToolbarState();
}

class _InspectToolbarState extends State<_InspectToolbar> {
  Offset? _pos;
  static const double _w = 268;
  static const double _h = 66;
  static const _accent = Color(0xFF4FC3F7);

  void _drag(Offset delta, Size screen, double safeTop, double safeBottom) {
    final cur = _pos ?? Offset(12, safeTop + 8);
    final nx = (cur.dx + delta.dx).clamp(4.0, screen.width - _w - 4);
    final ny = (cur.dy + delta.dy).clamp(
      safeTop + 4,
      screen.height - _h - safeBottom - 4,
    );
    setState(() => _pos = Offset(nx, ny));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final pos = _pos ?? Offset((screen.width - _w) / 2, pad.top + 8);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _w,
          decoration: BoxDecoration(
            color: const Color(0xF2141A21),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerMove:
                        (e) => _drag(e.delta, screen, pad.top, pad.bottom),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        color: Colors.white24,
                        size: 18,
                      ),
                    ),
                  ),
                  Expanded(child: _segmented()),
                  _iconBtn(
                    Icons.layers_clear_outlined,
                    widget.hasSelection ? widget.onClear : null,
                  ),
                  _iconBtn(Icons.close, widget.onClose),
                ],
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 12,
                      color: Colors.white30,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        widget.hint,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  Widget _segmented() {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          _seg('Inspect', Icons.center_focus_strong, widget.pickMode, true),
          _seg('Browse', Icons.pan_tool_alt_outlined, !widget.pickMode, false),
        ],
      ),
    );
  }

  Widget _seg(String label, IconData icon, bool active, bool pick) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSetMode(pick),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                active ? _accent.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? _accent : Colors.white54),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: active ? _accent : Colors.white54,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Colors.white60 : Colors.white24,
        ),
      ),
    );
  }
}

