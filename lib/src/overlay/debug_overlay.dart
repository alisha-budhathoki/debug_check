import 'dart:convert';
import 'dart:math' as math;

import 'package:debug_deck/debug_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'api_detail.dart';
part 'app_info_panel.dart';
part 'detail_widgets.dart';
part 'formatting.dart';
part 'log_list.dart';
part 'perf_panel.dart';

/// Mounted once via `MaterialApp.router`'s `builder` so it floats above every
/// route — including when launched from a native add-to-app host. Renders
/// nothing in release builds.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

const double _chipSize = 38;
const Color _chipColorOk = Color(0xFF2E7D32);
const Color _chipColorError = Color(0xFFC62828);

final ThemeData _kDebugOverlayTheme = ThemeData.dark(
  useMaterial3: true,
).copyWith(
  scaffoldBackgroundColor: const Color(0xFF0E1116),
  canvasColor: const Color(0xFF0E1116),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF61AFEF),
    surface: Color(0xFF0E1116),
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: Colors.white70,
    selectionColor: Color(0x5561AFEF),
    selectionHandleColor: Color(0xFF61AFEF),
  ),
  iconTheme: const IconThemeData(color: Colors.white),
);

class _DebugOverlayState extends State<DebugOverlay>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Offset> _position = ValueNotifier<Offset>(
    const Offset(12, 120),
  );
  bool _viewerOpen = false;
  // Once opened, the viewer stays mounted (just Offstage when closed) so its
  // whole navigation state — filter tab, search, the open API detail, that
  // detail's tab index and every scroll offset — survives a minimize→app→reopen
  // round-trip. Lazy so we pay nothing until the dev first taps the chip.
  bool _viewerMounted = false;
  bool _hidden = false;
  Size? _cachedScreenSize;

  // Drives the circular "burst open" reveal. Linear here; the curve + clip are
  // applied in the builder. Origin is captured from the chip so the panel
  // appears to erupt from wherever the bug button is sitting.
  late final AnimationController _reveal;
  Offset _revealOrigin = const Offset(30, 140);

  // Stable identity for the viewer subtree. The reveal builder swaps it between
  // a bare child (fully open) and a wrapped child (animating/minimized); a
  // GlobalKey makes Flutter *move* the existing element instead of rebuilding
  // it, so the preserved navigation, scroll and open detail survive minimize.
  final GlobalKey _viewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedScreenSize = MediaQuery.sizeOf(context);
  }

  @override
  void dispose() {
    _reveal.dispose();
    _position.dispose();
    super.dispose();
  }

  void _handleDrag(Offset delta) {
    final size = _cachedScreenSize ?? MediaQuery.sizeOf(context);
    final current = _position.value;
    final newX = (current.dx + delta.dx).clamp(0.0, size.width - _chipSize);
    final newY = (current.dy + delta.dy).clamp(0.0, size.height - _chipSize);
    _position.value = Offset(newX, newY);
  }

  void _toggleViewer() => _viewerOpen ? _minimizeViewer() : _openViewer();

  void _openViewer() {
    _revealOrigin =
        _position.value + const Offset(_chipSize / 2, _chipSize / 2);
    HapticFeedback.mediumImpact();
    setState(() {
      _viewerMounted = true;
      _viewerOpen = true;
    });
    _reveal.forward();
  }

  // Minimize: reverse the reveal but keep the subtree alive, so state survives
  // a reopen.
  void _minimizeViewer() {
    setState(() => _viewerOpen = false);
    _reveal.reverse();
  }

  // Close: reverse, then unmount so its State is disposed — the next open builds
  // a fresh viewer from the first screen (log list, no filter/search/detail).
  void _closeViewer() {
    setState(() => _viewerOpen = false);
    _reveal.reverse().whenComplete(() {
      if (!_viewerOpen && mounted) setState(() => _viewerMounted = false);
    });
  }

  void _hideOverlay() {
    setState(() => _viewerOpen = false);
    _reveal.reverse().whenComplete(() {
      if (!_viewerOpen && mounted) {
        setState(() {
          _viewerMounted = false;
          _hidden = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Visible only when the native host hands us a `dev` environment.
    // Hidden in production regardless of build mode.
    if (!DebugTools.enabled || _hidden) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Layout/spacing grid — paints above app content, below the viewer/chip.
        // Positioned.fill so this never becomes a non-positioned child that
        // would collapse the Stack (and hide the chip) when the grid is off.
        const Positioned.fill(child: DebugGridLayer()),
        // Mounted once, then kept alive (Offstage when fully closed) so closing
        // only minimizes it (state preserved) rather than tearing it down.
        // While the reveal animates, it bursts open from the chip via a circular
        // clip + scrim + fade/scale; once fully open the builder returns the bare
        // child so there's zero steady-state transform/clip overhead.
        if (_viewerMounted)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _reveal,
              // `child` is built once and must always be returned somewhere in
              // the tree, or the viewer's State (and its preserved navigation)
              // would be disposed.
              child: RepaintBoundary(
                key: _viewerKey,
                child: _LogViewerHost(
                  onMinimize: _minimizeViewer,
                  onClose: _closeViewer,
                  onHide: _hideOverlay,
                ),
              ),
              builder: (context, child) {
                final t = _reveal.value;
                if (_viewerOpen && t >= 1.0) return child!;
                final visible = _viewerOpen || t > 0.001;
                return Offstage(
                  offstage: !visible,
                  child: TickerMode(
                    enabled: visible,
                    child: IgnorePointer(
                      ignoring: !_viewerOpen,
                      child: _RevealTransition(
                        origin: _revealOrigin,
                        fraction: Curves.easeOutCubic.transform(
                          t.clamp(0.0, 1.0),
                        ),
                        opacity: t.clamp(0.0, 1.0),
                        child: child!,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ValueListenableBuilder<Offset>(
          valueListenable: _position,
          builder: (context, pos, child) {
            // While the full-screen viewer is open the chip is redundant (the
            // header carries minimize/close/hide) and would just overlap the
            // content, so it's hidden until the viewer is minimized or closed.
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: Offstage(offstage: _viewerOpen, child: child!),
            );
          },
          child: RepaintBoundary(
            child: _ChipHost(onTap: _toggleViewer, onDrag: _handleDrag),
          ),
        ),
      ],
    );
  }
}

/// The "big open" effect: dims the app, then reveals the viewer through a circle
/// that grows from [origin] (the chip), with a slight fade + scale-up.
class _RevealTransition extends StatelessWidget {
  final Offset origin;
  final double fraction; // 0..1, already eased
  final double opacity; // 0..1
  final Widget child;
  const _RevealTransition({
    required this.origin,
    required this.fraction,
    required this.opacity,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.55 * opacity),
          ),
        ),
        ClipPath(
          clipper: _RevealClipper(origin: origin, fraction: fraction),
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: 0.96 + 0.04 * fraction, child: child),
          ),
        ),
      ],
    );
  }
}

class _RevealClipper extends CustomClipper<Path> {
  final Offset origin;
  final double fraction;
  const _RevealClipper({required this.origin, required this.fraction});

  @override
  Path getClip(Size size) {
    final maxR = _maxRadius(size);
    final r = (maxR * fraction).clamp(0.0, maxR);
    return Path()..addOval(Rect.fromCircle(center: origin, radius: r));
  }

  double _maxRadius(Size s) {
    final dx = math.max(origin.dx, s.width - origin.dx);
    final dy = math.max(origin.dy, s.height - origin.dy);
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool shouldReclip(_RevealClipper old) =>
      old.fraction != fraction || old.origin != origin;
}

class _ChipHost extends StatelessWidget {
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;
  const _ChipHost({required this.onTap, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DebugLogCounts>(
      valueListenable: DebugLogger.instance.counts,
      builder: (context, counts, _) {
        return _DraggableChip(
          count: counts.total,
          errorCount: counts.errors,
          onTap: onTap,
          onDrag: onDrag,
        );
      },
    );
  }
}

class _LogViewerHost extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback onHide;
  const _LogViewerHost({
    required this.onMinimize,
    required this.onClose,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) {
            return ValueListenableBuilder<List<DebugLogEntry>>(
              valueListenable: DebugLogger.instance.entries,
              builder: (context, entries, _) {
                // Pin the debug theme so the viewer (log list + the API detail
                // tabs) never inherits the host/native app theme.
                return Theme(
                  data: _kDebugOverlayTheme,
                  child: _DebugLogViewer(
                    entries: entries,
                    onMinimize: onMinimize,
                    onClose: onClose,
                    onHide: onHide,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ─── Chip ────────────────────────────────────────────────────────────────────

class _DraggableChip extends StatefulWidget {
  final int count;
  final int errorCount;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;

  const _DraggableChip({
    required this.count,
    required this.errorCount,
    required this.onTap,
    required this.onDrag,
  });

  @override
  State<_DraggableChip> createState() => _DraggableChipState();
}

class _DraggableChipState extends State<_DraggableChip> {
  static const double _dragSlop = 4;
  Offset? _downPosition;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _downPosition = event.position;
        _isDragging = false;
      },
      onPointerMove: (event) {
        final start = _downPosition;
        if (start == null) return;
        if (!_isDragging) {
          if ((event.position - start).distance < _dragSlop) return;
          _isDragging = true;
        }
        widget.onDrag(event.delta);
      },
      onPointerUp: (event) {
        if (!_isDragging) widget.onTap();
        _downPosition = null;
        _isDragging = false;
      },
      onPointerCancel: (_) {
        _downPosition = null;
        _isDragging = false;
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _chipSize,
          height: _chipSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors:
                  widget.errorCount > 0
                      ? const [Color(0xFFE53935), _chipColorError]
                      : const [Color(0xFF43A047), _chipColorOk],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.bug_report_rounded,
                color: Colors.white,
                size: 22,
              ),
              if (widget.count > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            widget.errorCount > 0
                                ? _chipColorError
                                : _chipColorOk,
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.count > 99 ? '99+' : '${widget.count}',
                      style: TextStyle(
                        color:
                            widget.errorCount > 0
                                ? _chipColorError
                                : _chipColorOk,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
